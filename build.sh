#!/bin/bash
set -euo pipefail

echo "::notice title=Helm::$(helm version)"

# Extract variables from the template file using envsubst
TEMPLATE_FILE="charts/argocd-applications/application.yaml.tmpl"
if [[ ! -f $TEMPLATE_FILE ]]; then
	echo "Error: Template file $TEMPLATE_FILE not found"
	exit 1
fi

# Get list of variables from template (envsubst -v outputs variable names)
# Sort and deduplicate to handle variables that appear multiple times
VARIABLES=$(envsubst -v "$(cat "$TEMPLATE_FILE")" 2>/dev/null | sort -u || true)

# Build helm args array for API versions (used only for template, not lint)
helm_template_args=()
while IFS= read -r api_version; do
	# Skip empty lines
	[[ -z $api_version ]] && continue
	helm_template_args+=(-a "${api_version}")
done <charts/extract-apis/helm-api-versions.txt

# Get kube version (used only for template, not lint)
KUBE_VERSION=$(tr -d '[:space:]' <charts/extract-apis/helm-kube-version.txt)
helm_template_args+=(--kube-version "${KUBE_VERSION}")

# Build --set flags for all variables with placeholder values
set_flags=()
while IFS= read -r var; do
	# Skip empty lines
	[[ -z $var ]] && continue
	# Set default placeholder value for each variable (include var name for easier troubleshooting)
	set_flags+=(--set "${var}=placeholder")
done <<<"$VARIABLES"

for chart in charts/*; do
	if [[ ! -f "$chart/Chart.yaml" ]]; then
		continue
	fi
	name=$(basename "$chart")
	echo "::group::Linting $name at $chart"
	pushd "$chart"
	# We do NOT dep update here because we might have cached it.
	echo "Linting $chart"
	helm lint --strict . \
		"${set_flags[@]}"

	echo "Templating $chart"
	helm template "${name}" . --namespace "${name}" \
		--skip-crds \
		"${helm_template_args[@]}" \
		"${set_flags[@]}" \
		>rendered.yaml
	echo "Done templating $chart"
	popd
	echo "::endgroup::"
done
