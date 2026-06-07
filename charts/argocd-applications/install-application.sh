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

# Push Argo CD's generated initial admin password into the existing 1Password login
# item for this cluster (e.g. argocd-tiles-admin, argocd-tiles-test-admin).
sync_argocd_admin_password_to_onepassword() {
	if [[ ${INSTALL_APPLICATION_SKIP_ARGOCD_ADMIN_PASSWORD_SYNC:-} == "true" ]]; then
		echo "INSTALL_APPLICATION_SKIP_ARGOCD_ADMIN_PASSWORD_SYNC=true; skipping Argo CD admin password sync"
		return 0
	fi

	if [[ -z ${vault_name:-} ]]; then
		echo "ERROR: vault_name not set (required for Argo CD admin password sync to 1Password)"
		exit 1
	fi

	local op_item="argocd-${cluster_name}-admin"

	if ! command -v op >/dev/null 2>&1; then
		echo "WARNING: op CLI not found; skipping Argo CD admin password sync (${op_item})"
		return 0
	fi

	if [[ -z ${OP_SERVICE_ACCOUNT_TOKEN:-} ]] && ! op account list >/dev/null 2>&1; then
		echo "WARNING: no OP_SERVICE_ACCOUNT_TOKEN and no op session; skipping Argo CD admin password sync (${op_item})"
		return 0
	fi

	wait_prereq "Secret argocd-initial-admin-secret" \
		kubectl get secret argocd-initial-admin-secret -n "${ARGOCD_NAMESPACE}"

	local password
	password="$(
		kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
			-o jsonpath='{.data.password}' | base64 -d
	)"

	if [[ -z ${password} ]]; then
		echo "ERROR: argocd-initial-admin-secret password field is empty"
		exit 1
	fi

	# set -x would echo the password argument; disable tracing for the edit.
	set +x
	op item edit "${op_item}" --vault "${vault_name}" "password=${password}"
	local edit_status=$?
	password=''
	unset password
	set -x

	if ((edit_status != 0)); then
		echo "ERROR: failed to update 1Password item ${op_item} in vault ${vault_name}"
		exit 1
	fi

	echo "Updated 1Password item ${op_item} (vault ${vault_name}) with Argo CD initial admin password"
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

echo "::group::Sync Argo CD initial admin password to 1Password"
sync_argocd_admin_password_to_onepassword
echo "::endgroup::"

echo "::group::Install ArgoCD Applications"
envsubst <charts/argocd-applications/application.yaml.tmpl | kubectl apply --server-side --force-conflicts -f-
echo "::endgroup::"
