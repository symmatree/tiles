#!/bin/bash
set -euo pipefail

echo "::group::Bootstrap Cilium"
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
helm template cilium charts/cilium --namespace cilium \
	--skip-crds \
	--set "cilium.ipv4NativeRoutingCIDR=${pod_cidr:?}" \
	--set "cilium.cluster.name=${cluster_name:?}" \
	--set "cilium.hubble.ui.ingress.hosts[0]=hubble.${cluster_name:?}.symmatree.com" \
	--set "cilium.hubble.ui.ingress.tls[0].secretName=hubble-ui-tls" \
	--set "cilium.hubble.ui.ingress.tls[0].hosts[0]=hubble.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
set +x
echo "::endgroup::"
