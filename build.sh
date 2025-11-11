#!/bin/bash
set -euxo pipefail

for chart in charts/*; do
	if [[ ! -f "$chart/Chart.yaml" ]]; then
		continue
	fi
	name=$(basename "$chart")
	pushd "$chart"
	helm dep update
	helm lint
	helm template "$name" . --namespace "$name" >rendered.yaml
	popd
done
