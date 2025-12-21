#!/bin/bash
set -euo pipefail

echo "::notice title=Helm::$(helm version)"

# Source the helper script to set up helm_template_args and set_flags
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/helm-common.bash"

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
