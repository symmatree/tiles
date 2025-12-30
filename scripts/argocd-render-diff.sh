#!/bin/bash
set -euo pipefail

# Script to render ArgoCD applications and diff against live cluster
# This script:
# 1. Renders the argocd-applications chart using helm with terraform outputs
# 2. Uses argocd CLI to diff each application against the live cluster
# 3. Renders each application to {cluster_name}-rendered.yaml in its chart directory
# 4. Saves diffs to txt-outputs directory for PR comments

# Ensure required environment variables are set
: "${cluster_name:?cluster_name is required}"
: "${targetRevision:?targetRevision is required}"

# Optional: directory for text outputs (defaults to /tmp/txt-outputs)
TXT_OUTPUT_DIR="${TXT_OUTPUT_DIR:-/tmp/txt-outputs}"
mkdir -p "${TXT_OUTPUT_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Get current git branch/ref for overriding target revision
CURRENT_REF="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}}"
echo "Current ref: ${CURRENT_REF}"

echo "::group::Install ArgoCD CLI"
# Install argocd CLI if not already installed
if ! command -v argocd &>/dev/null; then
	echo "Installing argocd CLI..."
	ARGOCD_VERSION="v2.13.2"
	curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
	chmod +x /tmp/argocd
	sudo mv /tmp/argocd /usr/local/bin/argocd
	echo "ArgoCD CLI installed: $(argocd version --client)"
else
	echo "ArgoCD CLI already installed: $(argocd version --client)"
fi
echo "::endgroup::"

echo "::group::Login to ArgoCD"
# Login to ArgoCD using direct access via ingress
# We're on the VPN and can access argocd.{cluster_name}.symmatree.com directly
ARGOCD_SERVER="argocd.${cluster_name}.symmatree.com"
echo "Connecting to ArgoCD at ${ARGOCD_SERVER}"

# Login using kubernetes auth (no password needed with --core flag)
# The --core flag uses kubectl directly for auth instead of the API server
argocd login "${ARGOCD_SERVER}" --core --insecure
echo "::endgroup::"

echo "::group::Set kubectl namespace to argocd"
# Set the current kubectl namespace context to "argocd"
# The argocd CLI uses the current namespace context when interacting with the cluster
kubectl config set-context --current --namespace=argocd
echo "Current namespace set to: $(kubectl config view --minify -o jsonpath='{..namespace}')"
echo "::endgroup::"

echo "::group::Render argocd-applications with Helm"
# First, render the argocd-applications chart to get the list of applications
cd "${REPO_ROOT}/charts/argocd-applications"

helm_template_args=()
set_flags=()

# Source the helper script to set up helm_template_args and set_flags
# shellcheck source=scripts/helm-common.bash
source "${REPO_ROOT}/scripts/helm-common.bash"

# Render the chart
helm template argocd-applications . --namespace argocd \
	--skip-crds \
	"${helm_template_args[@]}" \
	"${set_flags[@]}" \
	>"${cluster_name}-rendered.yaml"

echo "Rendered argocd-applications to ${cluster_name}-rendered.yaml"
echo "::endgroup::"

# Extract application names from the rendered YAML
echo "::group::Extract application names"
APP_NAMES=$(yq eval 'select(.kind == "Application") | .metadata.name' "${cluster_name}-rendered.yaml" | sort -u)
echo "Applications found:"
echo "${APP_NAMES}"
echo "::endgroup::"

# For each application, render and diff
for app_name in ${APP_NAMES}; do
	echo "::group::Render and diff ${app_name}"

	# Get the application spec from the rendered YAML
	app_yaml=$(mktemp)
	yq eval "select(.kind == \"Application\" and .metadata.name == \"${app_name}\")" \
		"${cluster_name}-rendered.yaml" >"${app_yaml}"

	# Extract source details
	repo_url=$(yq eval '.spec.source.repoURL' "${app_yaml}")
	target_revision=$(yq eval '.spec.source.targetRevision' "${app_yaml}")
	path=$(yq eval '.spec.source.path' "${app_yaml}")
	namespace=$(yq eval '.spec.destination.namespace' "${app_yaml}")

	echo "Application: ${app_name}"
	echo "  Repo: ${repo_url}"
	echo "  Revision: ${target_revision}"
	echo "  Path: ${path}"
	echo "  Namespace: ${namespace}"

	# Override target revision if the source repo is the tiles repo (same repo)
	effective_revision="${target_revision}"
	if [[ ${repo_url} == *"symmatree/tiles"* ]]; then
		effective_revision="${CURRENT_REF}"
		echo "  Using current branch/ref: ${effective_revision} (overriding ${target_revision})"
	fi

	# Prepare diff output file
	diff_output="${TXT_OUTPUT_DIR}/${app_name}-diff.txt"
	echo "ArgoCD Diff for ${app_name}" >"${diff_output}"
	echo "===========================================" >>"${diff_output}"
	echo "" >>"${diff_output}"

	# Run the diff using argocd app diff with --local flag
	# This works for helm, plugins (tanka), and other source types
	# The --local flag tells argocd to use the local path instead of fetching from git
	set +e
	argocd app diff "${app_name}" --local "${REPO_ROOT}/${path}" \
		--revision "${effective_revision}" | tee -a "${diff_output}" 2>&1
	diff_exit=$?
	set -e

	if [ ${diff_exit} -eq 0 ]; then
		echo "No differences detected" >>"${diff_output}"
	elif [ ${diff_exit} -eq 1 ]; then
		# Exit code 1 means differences were found, which is expected
		echo "" >>"${diff_output}"
	else
		echo "Diff command failed with exit code ${diff_exit}" >>"${diff_output}"
	fi

	# Always render the application manifests to the chart directory for reference
	# This creates a static snapshot of the intended state
	render_output="${REPO_ROOT}/${path}/${cluster_name}-rendered.yaml"
	echo "Rendering manifests to ${render_output}..."
	set +e
	argocd app manifests "${app_name}" --local "${REPO_ROOT}/${path}" \
		--revision "${effective_revision}" | tee "${render_output}" 2>&1
	render_exit=$?
	set -e

	if [ ${render_exit} -eq 0 ]; then
		echo "Manifests rendered successfully to ${render_output}"
	else
		echo "::warning::Failed to render manifests for ${app_name} (exit code ${render_exit})"
		rm -f "${render_output}"
	fi

	rm -f "${app_yaml}"
	echo "::endgroup::"
done

echo "::notice::ArgoCD render and diff complete. Outputs saved to ${TXT_OUTPUT_DIR}"
