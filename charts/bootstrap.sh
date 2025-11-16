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

for chart in cilium argocd; do
	if ! kubectl get namespace ${chart}; then
		kubectl create namespace ${chart}
		kubectl label namespace ${chart} "pod-security.kubernetes.io/warn=baseline" --overwrite
		kubectl label namespace ${chart} "pod-security.kubernetes.io/enforce=privileged" --overwrite
		kubectl label namespace ${chart} "trust-bundle=enabled" --overwrite
	fi
	pushd charts/${chart}
	# Some charts have default-namespace problems.
	set -x
	kubens ${chart}
	helm template ${chart} . --namespace ${chart} \
		--skip-crds \
		"${helm_args[@]}" |
		kubectl apply --server-side -f-
	set +x
	popd
done
