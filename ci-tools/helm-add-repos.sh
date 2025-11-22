#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")" >/dev/null
CI_TOOLS=$(pwd)
WORKSPACE=$(dirname "$CI_TOOLS")
echo "WORKSPACE: $WORKSPACE"
cd "${WORKSPACE}"
mapfile -t urls < <(find . -name "Chart.yaml" -exec yq ".dependencies[].repository" "{}" ';' | sort | uniq)
repo_num=1
for url in "${urls[@]}"; do
	if ! helm repo list | grep -q "$url"; then
		echo "Adding Helm repository: $url"
		helm repo add "$(basename "$url")-${repo_num}" "$url"
		((++repo_num))
	else
		echo "Found Helm repo for url, skipping: $url"
	fi
done
