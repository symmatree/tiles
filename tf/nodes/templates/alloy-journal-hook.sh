#!/usr/bin/env bash
# Proxmox hookscript for the Alloy monitoring CT (#686).
#
# Runs ON THE HOST as root at CT lifecycle phases. At pre-start it grants the CT's mapped root
# (host uid 100000 -- the default unprivileged idmap base 0->100000) read access to the host
# systemd journal, so Alloy's loki.source.journal can collect host logs from an UNPRIVILEGED CT
# (privileged is not an option: OCI-image containers fail to create privileged, bpg#2513).
#
# SAFETY: this MUST always exit 0. A non-zero pre-start hook aborts the CT start. Every step is
# best-effort and non-fatal -- if the ACL can't be applied, host-log collection is skipped for this
# boot but the CT (and its metrics) still come up. Kept noisy (logs to the file below + stderr,
# which lands in the Proxmox task log) until we trust it.
#
# Args: $1 = vmid, $2 = phase (pre-start|post-start|pre-stop|post-stop).
set +e

VMID="$1"
PHASE="$2"
JOURNAL_DIR="/var/log/journal"
CT_MAPPED_UID="100000" # unprivileged CT: container root (0) -> host 100000 (default idmap)
LOG="/var/log/alloy-journal-hook.log"

log() { echo "[$(date -Is 2>/dev/null)] alloy-journal-hook vmid=${VMID} phase=${PHASE}: $*" | tee -a "$LOG" >&2; }

if [ "$PHASE" != "pre-start" ]; then
	exit 0
fi

log "pre-start: granting u:${CT_MAPPED_UID} read on ${JOURNAL_DIR}"

if [ ! -d "$JOURNAL_DIR" ]; then
	log "WARNING: ${JOURNAL_DIR} does not exist (no persistent journal?); skipping"
	exit 0
fi

if ! command -v setfacl >/dev/null 2>&1; then
	log "setfacl missing; installing the 'acl' package"
	# Bounded so a slow/unreachable mirror at boot can't stall the CT start (the whole hook is pre-start).
	if timeout 90 apt-get -o DPkg::Lock::Timeout=60 install -y acl >>"$LOG" 2>&1; then
		log "acl installed"
	else
		log "WARNING: acl install failed/timed out (rc=$?); host-log collection skipped this boot"
		exit 0
	fi
fi

# Access ACL for existing journal files, plus a default ACL so journald's newly-rotated files inherit it.
if setfacl -R -m "u:${CT_MAPPED_UID}:rX" "$JOURNAL_DIR" >>"$LOG" 2>&1; then
	log "access ACL applied"
else
	log "WARNING: access ACL failed (rc=$?)"
fi
if setfacl -R -d -m "u:${CT_MAPPED_UID}:rX" "$JOURNAL_DIR" >>"$LOG" 2>&1; then
	log "default ACL applied"
else
	log "WARNING: default ACL failed (rc=$?)"
fi

log "done"
exit 0
