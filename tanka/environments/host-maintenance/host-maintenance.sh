#!/usr/bin/env bash
# One step of the host-maintenance workflow. See README.md for what the workflow does.
#
#   host-maintenance.sh preflight | drain | update-reboot | wait-back | release | notify
#
# Parameters arrive as environment variables from the WorkflowTemplate:
#   KIND      pve (a Proxmox host: update packages, reboot it, its guests come back with it)
#             or talos (a bare-metal Talos node: reboot it)
#   TARGET    the Proxmox host name, or the Talos node's Kubernetes node name
#   NODES     space-separated Kubernetes nodes that go down with TARGET
#   WORKFLOW  this workflow's name; marks the nodes this run cordoned
# Outputs are files under /tmp/outputs, which the template exposes as output parameters.
set -euo pipefail

PVE_DOMAIN="${PVE_DOMAIN:-local.symmatree.com}"
SSH_KEY="${SSH_KEY:-/secrets/ssh/private-key}"
export TALOSCONFIG="${TALOSCONFIG:-/secrets/talos/notesPlain}"
CORDONED_BY=host-maintenance.symmatree.com/cordoned-by
OUT=/tmp/outputs
mkdir -p "$OUT"

log() { echo "$(date -u +%FT%TZ) $*"; }
die() {
	log "FAIL: $*"
	exit 1
}

# Run CMD every INTERVAL seconds until it succeeds, for at most TIMEOUT seconds.
retry() {
	local timeout=$1 interval=$2 deadline
	shift 2
	deadline=$(($(date +%s) + timeout))
	until "$@"; do
		[ "$(date +%s)" -lt "$deadline" ] || return 1
		sleep "$interval"
	done
}

pve() {
	# The key is mounted 0440 and ssh refuses a key others can read, so use a private copy.
	if [ ! -f /tmp/id ]; then install -m 0600 "$SSH_KEY" /tmp/id; fi
	ssh -n -i /tmp/id -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 \
		-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/known_hosts \
		"root@${TARGET}.${PVE_DOMAIN}" "$@"
}

node_ip() {
	kubectl get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'
}

boot_id() { kubectl get node "$1" -o jsonpath='{.status.nodeInfo.bootID}'; }

node_ready() {
	[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = True ]
}

all_nodes_ready() {
	local notready
	notready=$(kubectl get nodes -o json | jq -r '.items[]
    | select(([.status.conditions[] | select(.type == "Ready")][0].status) != "True")
    | .metadata.name')
	if [ -n "$notready" ]; then
		log "not Ready: $(echo "$notready" | tr '\n' ' ')"
		return 1
	fi
}

# Every control-plane node's etcd service is healthy, and the member list has one voting
# member per control-plane node.
etcd_healthy() {
	local ips ip members
	ips=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
		-o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
	for ip in $ips; do
		if ! grep -Eq '^HEALTH +OK$' <<<"$(talosctl -n "$ip" service etcd)"; then
			log "etcd on $ip is not healthy"
			return 1
		fi
	done
	members=$(talosctl -n "${ips%% *}" etcd members | awk 'NR > 1 && $NF == "false"' | wc -l)
	if [ "$members" -ne "$(echo "$ips" | wc -w)" ]; then
		log "etcd has $members voting members for $(echo "$ips" | wc -w) control-plane nodes"
		return 1
	fi
}

pve_quorate() {
	local pvecm
	pvecm=$(pve pvecm status) || return 1
	grep -Eq '^Quorate: +Yes' <<<"$pvecm" || {
		log "Proxmox cluster is not quorate"
		return 1
	}
	[ "$(awk '/^Expected votes:/ {print $3}' <<<"$pvecm")" = \
		"$(awk '/^Total votes:/ {print $3}' <<<"$pvecm")" ] || {
		log "Proxmox cluster is missing votes"
		return 1
	}
}

host_boot_id() { pve cat /proc/sys/kernel/random/boot_id; }

preflight() {
	local n
	for n in $NODES; do
		[ "$(kubectl get node "$n" -o jsonpath='{.spec.unschedulable}')" != true ] ||
			die "$n is already cordoned; leaving it alone"
	done
	all_nodes_ready || die "a node is not Ready"
	etcd_healthy || die "etcd is not healthy"
	if [ "$KIND" = pve ]; then
		pve_quorate || die "Proxmox cluster check failed"
	fi
	for n in $NODES; do echo "$n $(boot_id "$n")"; done >"$OUT/boot-ids"
	log "preflight ok"
}

drain() {
	local n
	for n in $NODES; do
		kubectl cordon "$n"
		kubectl annotate node "$n" --overwrite "$CORDONED_BY=$WORKFLOW"
	done
	for n in $NODES; do
		kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=15m
	done
}

update_reboot() {
	if [ "$KIND" = pve ]; then
		host_boot_id >"$OUT/host-boot-id"
		# shellcheck disable=SC2016 # expands on the host, not here
		pve 'set -e
      export DEBIAN_FRONTEND=noninteractive
      echo "kernel before: $(uname -r)"
      apt-get update
      apt list --upgradable 2>/dev/null
      apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
      echo "newest installed kernel: $(ls /boot | sed -n "s/^vmlinuz-//p" | sort -V | tail -1)"
      systemd-run --on-active=5 systemctl reboot'
	else
		: >"$OUT/host-boot-id"
		talosctl -n "$(node_ip "$TARGET")" reboot --wait=false
	fi
	log "reboot of $TARGET requested"
}

host_rebooted() {
	local now
	now=$(host_boot_id 2>/dev/null) || return 1
	[ -n "$now" ] && [ "$now" != "$HOST_BOOT_ID" ]
}

node_back() {
	local n=$1 before=$2
	[ "$(boot_id "$n")" != "$before" ] && node_ready "$n"
}

wait_back() {
	local n before
	if [ "$KIND" = pve ]; then
		retry 1800 20 host_rebooted || die "$TARGET did not come back within 30m"
		log "$TARGET is up: $(pve uname -r)"
		retry 600 15 pve_quorate || die "Proxmox cluster did not regain quorum"
	fi
	while read -r n before; do
		[ -n "$n" ] || continue
		retry 1800 15 node_back "$n" "$before" || die "$n did not come back Ready within 30m"
		log "$n is back and Ready"
	done <<<"$BOOT_IDS"
	retry 600 15 etcd_healthy || die "etcd did not recover"
	log "all back"
}

# Uncordon only what this run cordoned. Runs on exit whatever happened, so a failed run
# does not leave nodes cordoned, and a node someone else cordoned stays cordoned.
release() {
	local n
	for n in $NODES; do
		if [ "$(kubectl get node "$n" -o json | jq -r --arg k "$CORDONED_BY" '.metadata.annotations[$k] // ""')" = "$WORKFLOW" ]; then
			kubectl uncordon "$n"
			kubectl annotate node "$n" "$CORDONED_BY-"
		fi
	done
}

# Never fails: a notification that cannot be delivered must not change the run's outcome.
notify() {
	local body
	body=$(jq -n --arg t "host-maintenance $TARGET: $STATUS" \
		--arg b "workflow $WORKFLOW, nodes: $NODES${FAILURES:+, failures: $FAILURES}" \
		'{title: $t, body: $b}')
	curl -fsS -m 30 -H 'Content-Type: application/json' -d "$body" "$NOTIFY_URL" ||
		log "notify failed"
}

case "${1:-}" in
preflight) preflight ;;
drain) drain ;;
update-reboot) update_reboot ;;
wait-back) wait_back ;;
release) release ;;
notify) notify ;;
*) die "unknown step: ${1:-}" ;;
esac
