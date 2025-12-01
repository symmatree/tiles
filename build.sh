#!/bin/bash
set -euo pipefail

targetRevision=main
cluster_name=placeholder
pod_cidr=placeholder
vault_name=placeholder

echo "::notice title=Helm::$(helm version)"

# Build helm args array for API versions
helm_args=()
while IFS= read -r api_version; do
	helm_args+=(-a "${api_version}")
done <charts/extract-apis/helm-api-versions.txt

KUBE_VERSION=$(tr -d '[:space:]' <charts/extract-apis/helm-kube-version.txt)
helm_args+=(--kube-version "${KUBE_VERSION}")

for chart in charts/*; do
	if [[ ! -f "$chart/Chart.yaml" ]]; then
		continue
	fi
	name=$(basename "$chart")
	echo "::group::Linting $name at $chart"
	pushd "$chart"
	# We do NOT dep update here because we might have cached it.
	echo "Linting $chart"
	helm lint --strict .

	echo "Templating $chart"
	helm template "${name}" . --namespace "${name}" \
		--skip-crds \
		"${helm_args[@]}" \
		--set "targetRevision=$targetRevision" \
		--set "cluster_name=$cluster_name" \
		--set "pod_cidr=$pod_cidr" \
		--set "vault_name=$vault_name" \
		>rendered.yaml
	echo "Done templating $chart"
	popd
	echo "::endgroup::"
done
