#!/bin/bash
set -exuo pipefail

# Source the helper script to set up helm_template_args and set_flags
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/helm-common.bash"
cd "${REPO_ROOT}"

echo "::group::Bootstrap ArgoCD"
if [[ -z ${cluster_name:-} ]]; then
	echo "ERROR: cluster_name not set"
	exit 1
fi

argocd_cluster_values="${REPO_ROOT}/charts/argocd-applications/values/argocd-${cluster_name}-values.yaml"
if [[ ! -f $argocd_cluster_values ]]; then
	echo "ERROR: per-cluster values file not found: ${argocd_cluster_values}"
	exit 1
fi

kubectl delete namespace argocd --ignore-not-found
kubectl create namespace argocd
kubectl label namespace argocd "pod-security.kubernetes.io/warn=baseline" --overwrite
kubectl label namespace argocd "pod-security.kubernetes.io/enforce=privileged" --overwrite
kubectl label namespace argocd "trust-bundle=enabled" --overwrite
kubectl config set-context --current --namespace=argocd

# Mirror charts/argocd/application.yaml valueFiles (Argo cannot helm-template Application CRs here).
# helm_template_args and set_flags come from helm-common.bash (sourced above).
#
# The --set flags below must mirror every host in the valuesObject of
# charts/argocd/application.yaml. charts/argocd/values.yaml defaults these to
# argocd.placeholder.symmatree.com so the chart renders offline; any host not overridden
# here is applied to the live cluster with that literal placeholder, which publishes the
# wrong ingress host and opens an unsolvable ACME order until Argo CD self-heals it.
# shellcheck disable=SC2154
helm template argocd charts/argocd --namespace argocd \
	--skip-crds \
	"${helm_template_args[@]}" \
	"${set_flags[@]}" \
	-f charts/argocd-applications/values/argocd-values.yaml \
	-f "${argocd_cluster_values}" \
	--set "argo-cd.global.domain=argocd.${cluster_name:?}.symmatree.com" \
	--set "argo-cd.server.ingressGrpc.hostname=grpc-argocd.${cluster_name:?}.symmatree.com" \
	--set "oauth2-proxy.ingress.hosts[0]=argocd.${cluster_name:?}.symmatree.com" \
	--set "oauth2-proxy.ingress.tls[0].secretName=argocd-proxy-tls" \
	--set "oauth2-proxy.ingress.tls[0].hosts[0]=argocd.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
echo "::endgroup::"
