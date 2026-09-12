# No shebang; must be sourced.
# Bash helper script to set up Helm arguments from template variables and API versions
# Source this script to get helm_template_args and set_flags arrays

# Fail if script is executed directly instead of sourced
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
	echo "Error: This script must be sourced, not executed directly" >&2
	echo "Usage: source ${BASH_SOURCE[0]}" >&2
	exit 1
fi

# Calculate repo root (this script is in scripts/, so go up one level)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The propagated value set: the top-level keys of the app-of-apps chart's
# values.yaml, which is what Terraform fills in for the root Application and
# what that Application passes down to every child.
VALUES_FILE="${REPO_ROOT}/charts/app-of-apps/values.yaml"
if [[ ! -f $VALUES_FILE ]]; then
	echo "Error: values file $VALUES_FILE not found" >&2
	exit 1
fi

VARIABLES=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' "$VALUES_FILE" | cut -d: -f1 | sort -u || true)

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

# Build --set flags for all variables
# Use actual environment variable value if set, otherwise use placeholder
set_flags=()
while IFS= read -r var; do
	# Skip empty lines
	[[ -z $var ]] && continue
	# Use actual env var value if set, otherwise placeholder
	# ${!var} is indirect expansion (value of variable named by $var)
	# ${!var:-placeholder} provides default if unset or empty
	set_flags+=(--set "${var}=${!var:-placeholder}")
done <<<"$VARIABLES"
