#!/bin/bash
set -exuo pipefail

echo "::group::Bootstrap ArgoCD"
kubectl delete namespace argocd --ignore-not-found
kubectl create namespace argocd
kubectl label namespace argocd "pod-security.kubernetes.io/warn=baseline" --overwrite
kubectl label namespace argocd "pod-security.kubernetes.io/enforce=privileged" --overwrite
kubectl label namespace argocd "trust-bundle=enabled" --overwrite
kubectl config set-context --current --namespace=argocd

helm template argocd charts/argocd --namespace argocd \
	--skip-crds \
	--set "argo-cd.global.domain=argocd.${cluster_name:?}.symmatree.com" \
	--set "argo-cd.server.ingressGrpc.hostname=grpc-argocd.${cluster_name:?}.symmatree.com" |
	kubectl apply --server-side -f-
echo "::endgroup::"
