#!/bin/bash
set -euxo pipefail

targetRevision=main
cluster_name=placeholder
cluster_id=666
pod_cidr=placeholder
vault_name=placeholder

for chart in charts/*; do
	if [[ ! -f "$chart/Chart.yaml" ]]; then
		continue
	fi
	name=$(basename "$chart")
	pushd "$chart"
	# We do NOT dep update here because we might have cached it.
	helm lint --strict

	helm template "${name}" . --namespace "${name}" \
		--skip-crds \
		--set "targetRevision=$targetRevision" \
		--set "cluster_name=$cluster_name" \
		--set "cluster_id=$cluster_id" \
		--set "pod_cidr=$pod_cidr" \
		--set "vault_name=$vault_name" \
		>rendered.yaml
	#	| kubectl diff --server-side -f-
	popd
done
