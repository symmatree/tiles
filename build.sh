#!/bin/bash
set -euxo pipefail

for chart in charts/*; do
	if [[ ! -f "$chart/Chart.yaml" ]]; then
		continue
	fi
	pushd "$chart"
	helm dep update
	helm lint
	helm template test-release . >rendered.yaml
	popd
done
