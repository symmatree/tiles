#!/usr/bin/env bash
set -euo pipefail

# Generate API versions file from cluster using Helm's Capabilities.APIVersions
# Uses the extract-apis chart to get Capabilities data including KubeVersion

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/helm-api-versions.txt"
KUBE_VERSION_FILE="${SCRIPT_DIR}/helm-kube-version.txt"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Extracting API versions using Helm Capabilities from extract-apis chart..."

# Template the chart with --dry-run=server to get cluster capabilities
helm template --dry-run=server extract-apis "${SCRIPT_DIR}" >"${TEMP_DIR}/helm-output.yaml"

# Extract the embedded YAML from ConfigMap
yq -r '.data."api-versions.yaml"' "${TEMP_DIR}/helm-output.yaml" >"${TEMP_DIR}/api-versions.yaml"

# Extract APIVersions list
yq -r '.APIVersions[]' "${TEMP_DIR}/api-versions.yaml" | sort -u >"${OUTPUT_FILE}"

# Extract KubeVersion (format: Major.Minor)
KUBE_VERSION=$(yq -r '.KubeVersion.Version' "${TEMP_DIR}/api-versions.yaml" | sed 's/^v\?\([0-9]\+\.[0-9]\+\).*/\1/')
echo "${KUBE_VERSION}" >"${KUBE_VERSION_FILE}"

echo "Successfully generated ${OUTPUT_FILE} with $(wc -l <"${OUTPUT_FILE}") API versions"
echo "Successfully generated ${KUBE_VERSION_FILE} with version ${KUBE_VERSION}"
