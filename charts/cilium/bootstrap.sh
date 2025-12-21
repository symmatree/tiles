#!/bin/bash
set -euo pipefail

# Source the helper script to set up helm_template_args and config_set_flags
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/helm-common.bash"
cd "${REPO_ROOT}"

echo "::group::Bootstrap Cilium"
# Verify required variables are set (subset of CONFIG_VARS needed for cilium)
required_vars=(
	"pod_cidr"
	"cluster_name"
)

for var in "${required_vars[@]}"; do
	if [[ -z ${!var:-} ]]; then
		echo "ERROR: $var not set"
		exit 1
	fi
done

set -x
kubectl delete namespace cilium --ignore-not-found

kubectl create namespace cilium
kubectl label namespace cilium "pod-security.kubernetes.io/warn=baseline" --overwrite
kubectl label namespace cilium "pod-security.kubernetes.io/enforce=privileged" --overwrite
kubectl config set-context --current --namespace=cilium

# Use config_set_flags which contains all config variables from the environment.
# Additional --set flags override computed values that ArgoCD will also set.
helm template cilium charts/cilium --namespace cilium \
	--skip-crds \
	"${helm_template_args[@]}" \
	"${config_set_flags[@]}" \
	--set "cilium.ipv4NativeRoutingCIDR=${pod_cidr:?}" \
	--set "cilium.cluster.name=${cluster_name:?}" \
	--set "cilium.hubble.ui.ingress.hosts[0]=hubble.${cluster_name:?}.symmatree.com" \
	--set "cilium.hubble.ui.ingress.tls[0].secretName=hubble-ui-tls" \
	--set "cilium.hubble.ui.ingress.tls[0].hosts[0]=hubble.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
set +x
echo "::endgroup::"
