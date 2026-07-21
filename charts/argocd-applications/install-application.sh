#!/usr/bin/env bash
# Install the root app-of-apps Application. Waits for Argo CD prerequisites only
# (not for sync). See charts/argocd-applications/README.md and docs/config-propagation.md.
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
# Total wall time ~= ATTEMPTS * SLEEP_SECS (default 24 * 10s = 4m).
ATTEMPTS="${INSTALL_APPLICATION_PREREQ_ATTEMPTS:-24}"
SLEEP_SECS="${INSTALL_APPLICATION_PREREQ_SLEEP_SECS:-10}"

if [[ -z ${cluster_name:-} ]]; then
	echo "ERROR: cluster_name not set (required for AppProject check and application.yaml.tmpl)"
	exit 1
fi

prereq_fail() {
	echo "ERROR: $1"
	echo "argocd-applications install needs Argo CD bootstrapped first (AppProject + controller + repo-server)."
	echo "Cold start: bootstrap-cluster with crds, cilium, argocd, onepassword enabled, then argocd_applications."
	echo "Or run: charts/argocd/bootstrap.sh with cluster_name and related env from 1Password misc-config."
	exit 1
}

wait_prereq() {
	local description=$1
	shift
	local attempt=1
	while ((attempt <= ATTEMPTS)); do
		if "$@"; then
			echo "Prerequisite ready: ${description}"
			return 0
		fi
		echo "Waiting for ${description} (attempt ${attempt}/${ATTEMPTS})..."
		sleep "${SLEEP_SECS}"
		((attempt += 1))
	done
	prereq_fail "Timed out after ${ATTEMPTS} attempts (~$((ATTEMPTS * SLEEP_SECS))s) waiting for: ${description}"
}

echo "::group::Wait for Argo CD prerequisites"
if [[ ${INSTALL_APPLICATION_SKIP_PREREQ_WAIT:-} == "true" ]]; then
	echo "INSTALL_APPLICATION_SKIP_PREREQ_WAIT=true; skipping prerequisite waits"
else
	wait_prereq "namespace ${ARGOCD_NAMESPACE}" \
		kubectl get namespace "${ARGOCD_NAMESPACE}"

	wait_prereq "AppProject ${cluster_name}" \
		kubectl get appproject "${cluster_name}" -n "${ARGOCD_NAMESPACE}"

	wait_prereq "Deployment argocd-redis" \
		kubectl wait --for=condition=available "deployment/argocd-redis" \
		-n "${ARGOCD_NAMESPACE}" --timeout=15s

	wait_prereq "Deployment argocd-repo-server" \
		kubectl wait --for=condition=available "deployment/argocd-repo-server" \
		-n "${ARGOCD_NAMESPACE}" --timeout=15s

	wait_prereq "StatefulSet argocd-application-controller" \
		kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
		"statefulset/argocd-application-controller" \
		-n "${ARGOCD_NAMESPACE}" --timeout=15s
fi
echo "::endgroup::"

echo "::group::Install ArgoCD Applications"
envsubst <charts/argocd-applications/application.yaml.tmpl | kubectl apply --server-side --force-conflicts -f-
echo "::endgroup::"

# Sync the auto-generated Argo CD initial admin password into the existing
# 1Password login item (argocd-{cluster_name}-admin), so operators don't have to
# kubectl-copy-paste it by hand after every bootstrap/reinstall. Best-effort: a
# failure here never aborts the bootstrap (the apps above are already applied) --
# it logs a clear WARNING with the manual fallback instead. The manual step
# remains documented in charts/argocd/README.md.
echo "::group::Sync Argo CD admin password to 1Password"
# Tracing is on (set -x) for the rest of the script; turn it OFF here so the
# password is never echoed to the workflow log. This block is last, so we do not
# restore it.
set +x
sync_argocd_admin_password() {
	if [[ ${INSTALL_APPLICATION_SKIP_ARGOCD_ADMIN_PASSWORD_SYNC:-} == "true" ]]; then
		echo "INSTALL_APPLICATION_SKIP_ARGOCD_ADMIN_PASSWORD_SYNC=true; skipping admin password sync"
		return 0
	fi

	local item="${ARGOCD_ADMIN_OP_ITEM:-argocd-${cluster_name}-admin}"
	local vault="${ARGOCD_ADMIN_OP_VAULT:-${vault_name:-}}"
	local field="${ARGOCD_ADMIN_OP_FIELD:-password}"

	if ! command -v op >/dev/null 2>&1; then
		echo "op CLI not found; skipping admin password sync (update '${item}' manually)"
		return 0
	fi
	if [[ -z ${vault} ]]; then
		echo "WARNING: no vault set (ARGOCD_ADMIN_OP_VAULT or vault_name); skipping admin password sync" >&2
		return 0
	fi
	if ! op whoami >/dev/null 2>&1; then
		echo "op not signed in / no OP_SERVICE_ACCOUNT_TOKEN; skipping admin password sync (update '${item}' manually)"
		return 0
	fi

	# argocd-initial-admin-secret exists only until the password is first changed
	# (Argo CD deletes it thereafter). Wait briefly; if it never appears, there is
	# nothing to sync.
	local pw="" attempt=1 max=6
	while ((attempt <= max)); do
		if pw=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
			-o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null) && [[ -n ${pw} ]]; then
			break
		fi
		echo "Waiting for argocd-initial-admin-secret (attempt ${attempt}/${max})..."
		sleep 5
		((attempt += 1))
	done
	if [[ -z ${pw} ]]; then
		echo "argocd-initial-admin-secret not present (already rotated?); nothing to sync"
		return 0
	fi

	# Update the existing password field with a plain `field=value` assignment.
	# `< /dev/null` is essential: `op item edit` reads stdin as a JSON *template*
	# whenever stdin is not a TTY (i.e. always in CI), and then fails with
	# "invalid JSON provided" -- unrelated to the assignment. Feeding it an empty
	# stdin makes it use only the assignment arg.
	# Capture op's stderr so a failure is diagnosable, but never print it if it
	# could contain the secret value.
	local op_err=""
	if op_err=$(op item edit "${item}" --vault "${vault}" "${field}=${pw}" </dev/null 2>&1 >/dev/null); then
		echo "Updated 1Password item '${item}' (vault '${vault}', field '${field}') with the current Argo CD admin password"
	else
		echo "WARNING: could not update 1Password item '${item}' in vault '${vault}'." >&2
		if [[ ${op_err} == *"${pw}"* ]]; then
			echo "  op: <error withheld: it referenced the secret value>" >&2
		else
			printf '  op: %s\n' "${op_err}" >&2
		fi
		echo "  Fallback: kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" >&2
	fi
	unset pw op_err
	return 0
}
sync_argocd_admin_password
echo "::endgroup::"
