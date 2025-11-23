#!/usr/bin/env bash
set -euo pipefail

required_vars=(
	"targetRevision"
	"pod_cidr"
	"cluster_name"
	"external_ip_cidr"
	"vault_name"
	"project_id"
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

set -x
helm template cilium charts/cilium --namespace cilium \
	--skip-crds \
	"${helm_args[@]}" \
	--set "cilium.ipv4NativeRoutingCIDR=${pod_cidr:?}" \
	--set "cilium.cluster.name=${cluster_name:?}" \
	--set "cilium.hubble.ui.ingress.hosts[0]=hubble.${cluster_name:?}.symmatree.com" \
	--set "cilium.hubble.ui.ingress.tls[0].secretName=hubble-ui-tls" \
	--set "cilium.hubble.ui.ingress.tls[0].hosts[0]=hubble.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
set +x

if ! kubectl get namespace argocd; then
	kubectl create namespace argocd
	kubectl label namespace argocd "pod-security.kubernetes.io/warn=baseline" --overwrite
	kubectl label namespace argocd "pod-security.kubernetes.io/enforce=privileged" --overwrite
	kubectl label namespace argocd "trust-bundle=enabled" --overwrite
fi
set -x
kubens argocd
helm template argocd charts/argocd --namespace argocd \
	--skip-crds \
	"${helm_args[@]}" \
	--set "argo-cd.global.domain=argocd.${cluster_name:?}.symmatree.com" \
	--set "argo-cd.server.ingressGrpc.hostname=grpc-argocd.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-

helm template argocd-applications charts/argocd-applications --namespace argocd \
	--skip-crds \
	"${helm_args[@]}" |
	kubectl apply --server-side -f-

set +x
