# No shebang; must be sourced.
# Bash helper script to set up Helm arguments from template variables and API versions
# Source this script to get helm_template_args, set_flags, and config_set_flags arrays

# Fail if script is executed directly instead of sourced
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
	echo "Error: This script must be sourced, not executed directly" >&2
	echo "Usage: source ${BASH_SOURCE[0]}" >&2
	exit 1
fi

# Calculate repo root (this script is in scripts/, so go up one level)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Canonical list of config variables from 1Password misc-config.
# These are Terraform outputs stored in 1Password for propagation to ArgoCD.
# Keep this list in sync with:
#   - .github/workflows/bootstrap-cluster.yaml (Load cluster config step)
#   - charts/argocd-applications/application.yaml.tmpl (valuesObject)
CONFIG_VARS=(
	targetRevision
	pod_cidr
	cluster_name
	external_ip_cidr
	vault_name
	project_id
	loki_bucket_chunks
	loki_bucket_ruler
	loki_bucket_admin
	mimir_bucket_blocks
	mimir_bucket_ruler
	mimir_bucket_alertmanager
)

# Build helm args array for API versions (used only for template, not lint)
helm_template_args=()
while IFS= read -r api_version; do
	# Skip empty lines
	[[ -z $api_version ]] && continue
	helm_template_args+=(-a "${api_version}")
done <"${REPO_ROOT}/charts/extract-apis/helm-api-versions.txt"

# Get kube version (used only for template, not lint)
KUBE_VERSION=$(tr -d '[:space:]' <"${REPO_ROOT}/charts/extract-apis/helm-kube-version.txt")
helm_template_args+=(--kube-version "${KUBE_VERSION}")

# Build --set flags for all config variables with placeholder values (for linting/CI)
set_flags=()
for var in "${CONFIG_VARS[@]}"; do
	set_flags+=(--set "${var}=placeholder")
done

# Build --set flags for all config variables with actual values from environment.
# Use this in bootstrap scripts to pass real values to helm template.
# Variables must be exported in the environment before sourcing this script.
config_set_flags=()
for var in "${CONFIG_VARS[@]}"; do
	if [[ -n ${!var:-} ]]; then
		config_set_flags+=(--set "${var}=${!var}")
	else
		# Fall back to placeholder if not set (allows partial bootstrap)
		config_set_flags+=(--set "${var}=placeholder")
	fi
done
