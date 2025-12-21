#!/bin/bash
set -exuo pipefail

# Source the helper script to set up helm_template_args and set_flags
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/helm-common.bash"
cd "${REPO_ROOT}"

echo "::group::Bootstrap ArgoCD"
kubectl delete namespace argocd --ignore-not-found
kubectl create namespace argocd
kubectl label namespace argocd "pod-security.kubernetes.io/warn=baseline" --overwrite
kubectl label namespace argocd "pod-security.kubernetes.io/enforce=privileged" --overwrite
kubectl label namespace argocd "trust-bundle=enabled" --overwrite
kubectl config set-context --current --namespace=argocd

helm template argocd charts/argocd --namespace argocd \
	--skip-crds \
	"${helm_template_args[@]}" \
	"${set_flags[@]}" \
	--set "argo-cd.global.domain=argocd.${cluster_name:?}.symmatree.com" \
	--set "argo-cd.server.ingressGrpc.hostname=grpc-argocd.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
echo "::endgroup::"
