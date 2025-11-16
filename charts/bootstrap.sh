#!/usr/bin/env bash
set -euo pipefail

required_vars=(
	"targetRevision"
	"cluster_name"
	"cluster_id"
	"pod_cidr"
	"vault_name"
	"external_ip_cidr"
)

# Build helm args array
helm_args=()
for var in "${required_vars[@]}"; do
	if [[ -z ${!var:-} ]]; then
		echo "ERROR: $var not set"
		exit 1
	fi
	# Accumulate --set arguments
	helm_args+=("--set" "${var}=${!var}")
done

if ! kubectl get namespace cilium; then
	kubectl create namespace cilium
	kubectl label namespace cilium "pod-security.kubernetes.io/warn=baseline" --overwrite
	kubectl label namespace cilium "pod-security.kubernetes.io/enforce=privileged" --overwrite
fi

pushd charts/cilium
set -x
kubens cilium
helm template cilium . --namespace cilium \
	--skip-crds \
	"${helm_args[@]}" \
	--set "cilium.ipv4NativeRoutingCIDR=${pod_cidr:?}" \
	--set "cilium.cluster.name=${cluster_name:?}" \
	--set "cilium.cluster.id=${cluster_id:?}" \
	--set "cilium.hubble.ui.ingress.hosts[0]=hubble.${cluster_name:?}.symmatree.com" \
	--set "cilium.hubble.ui.ingress.tls[0].secretName=hubble-ui-tls" \
	--set "cilium.hubble.ui.ingress.tls[0].hosts[0]=hubble.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
set +x
popd
if ! kubectl get namespace argocd; then
	kubectl create namespace argocd
	kubectl label namespace argocd "pod-security.kubernetes.io/warn=baseline" --overwrite
	kubectl label namespace argocd "pod-security.kubernetes.io/enforce=privileged" --overwrite
	kubectl label namespace argocd "trust-bundle=enabled" --overwrite
fi
pushd charts/argocd
set -x
kubens argocd
helm template argocd . --namespace argocd \
	--skip-crds \
	"${helm_args[@]}" \
	--set "argo-cd.global.domain=argocd.${cluster_name:?}.symmatree.com" \
	--set "argo-cd.server.ingressGrpc.hostname=grpc-argocd.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
set +x
