#!/usr/bin/env bash
set -euxo pipefail
pushd "$(dirname "$0")"
SAVE_DIR="$(pwd)"

helm dep update
popd

if ! kubectl get namespace argocd; then
	kubectl create namespace argocd &&
		kubectl label namespace argocd pod-security.kubernetes.io/warn=baseline
fi
helm template argocd "${SAVE_DIR}" --namespace argocd >"${SAVE_DIR}/manifest.yaml"
# Close to what argo itself will do.
kubens argocd
kubectl apply -f "${SAVE_DIR}/manifest.yaml" --context "admin@tiles-test" -n argocd --server-side
rm "${SAVE_DIR}/manifest.yaml"
