#! /usr/bin/env bash
set -euo pipefail

export PROMETHEUS_OPERATOR_VERSION="v0.86.2"
export CERT_MANAGER_VERSION="v1.19.1"
export ARGOCD_VERSION="v3.2.0"
export TRUST_MANAGER_VERSION="v0.20.2"
export ONEPASSWORD_OPERATOR_VERSION="v1.8.1"
export GATEWAY_API_VERSION="v1.4.0"
export ALLOY_OPERATOR_VERSION="alloy-operator-0.3.14"

set -x
kubectl apply --server-side -f "https://github.com/grafana/alloy-operator/releases/download/${ALLOY_OPERATOR_VERSION}/collectors.grafana.com_alloy.yaml"

# Prometheus Operator
kubectl apply --server-side -f "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd-full/monitoring.coreos.com_servicemonitors.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd-full/monitoring.coreos.com_podmonitors.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd-full/monitoring.coreos.com_probes.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd-full/monitoring.coreos.com_prometheusrules.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd-full/monitoring.coreos.com_scrapeconfigs.yaml"
# gateway-api
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
# cert-manager
kubectl apply --server-side -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml"
# trust-manager
kubectl apply --server-side -f "https://raw.githubusercontent.com/cert-manager/trust-manager/${TRUST_MANAGER_VERSION}/deploy/crds/trust.cert-manager.io_bundles.yaml"
# argo-cd
kubectl apply --server-side -f "https://raw.githubusercontent.com/argoproj/argo-cd/refs/tags/${ARGOCD_VERSION}/manifests/crds/application-crd.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/argoproj/argo-cd/refs/tags/${ARGOCD_VERSION}/manifests/crds/applicationset-crd.yaml"
kubectl apply --server-side -f "https://raw.githubusercontent.com/argoproj/argo-cd/refs/tags/${ARGOCD_VERSION}/manifests/crds/appproject-crd.yaml"
# onepassword-operator
kubectl apply --server-side -f "https://raw.githubusercontent.com/1Password/onepassword-operator/refs/tags/${ONEPASSWORD_OPERATOR_VERSION}/config/crd/bases/onepassword.com_onepassworditems.yaml"
# rollout-operator
kubectl apply --server-side -f https://raw.githubusercontent.com/grafana/helm-charts/main/charts/rollout-operator/crds/replica-templates-custom-resource-definition.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/grafana/helm-charts/main/charts/rollout-operator/crds/zone-aware-pod-disruption-budget-custom-resource-definition.yaml
set +x
