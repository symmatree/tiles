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
		kubectl wait --for=condition=ready "statefulset/argocd-application-controller" \
		-n "${ARGOCD_NAMESPACE}" --timeout=15s
fi
echo "::endgroup::"

echo "::group::Install ArgoCD Applications"
envsubst <charts/argocd-applications/application.yaml.tmpl | kubectl apply --server-side --force-conflicts -f-
echo "::endgroup::"
