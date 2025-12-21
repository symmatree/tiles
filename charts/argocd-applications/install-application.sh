#!/bin/bash
set -euo pipefail

echo "::group::Install ArgoCD Applications"
envsubst <charts/argocd-applications/application.yaml.tmpl | kubectl apply --server-side --force-conflicts -f-
echo "::endgroup::"
