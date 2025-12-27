#!/bin/bash
set -euo pipefail

# Script to render ArgoCD applications and diff against live cluster
# This script:
# 1. Renders the argocd-applications chart using helm with terraform outputs
# 2. Uses argocd CLI to render each application to {cluster_name}-rendered.yaml
# 3. Uses argocd CLI to diff against the live cluster
# 4. Saves diffs to txt-outputs directory for PR comments

# Ensure required environment variables are set
: "${cluster_name:?cluster_name is required}"
: "${targetRevision:?targetRevision is required}"

# Optional: directory for text outputs (defaults to /tmp/txt-outputs)
TXT_OUTPUT_DIR="${TXT_OUTPUT_DIR:-/tmp/txt-outputs}"
mkdir -p "${TXT_OUTPUT_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "::group::Install ArgoCD CLI"
# Install argocd CLI if not already installed
if ! command -v argocd &>/dev/null; then
	echo "Installing argocd CLI..."
	ARGOCD_VERSION="v2.13.2"
	curl -sSL -o /tmp/argocd "https://github.com/argoproj/argocd-cmd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
	chmod +x /tmp/argocd
	sudo mv /tmp/argocd /usr/local/bin/argocd
	echo "ArgoCD CLI installed: $(argocd version --client)"
else
	echo "ArgoCD CLI already installed: $(argocd version --client)"
fi
echo "::endgroup::"

echo "::group::Login to ArgoCD"
# Get ArgoCD server endpoint from the cluster
ARGOCD_SERVER=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "${ARGOCD_SERVER}" ]; then
	echo "::error::Failed to get ArgoCD server endpoint"
	exit 1
fi
echo "ArgoCD server: ${ARGOCD_SERVER}"

# Login to argocd (using kubeconfig auth)
argocd login "${ARGOCD_SERVER}" --core --grpc-web
echo "::endgroup::"

echo "::group::Render argocd-applications with Helm"
# First, render the argocd-applications chart to get the list of applications
cd "${REPO_ROOT}/charts/argocd-applications"

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

	# Try to diff against live cluster
	diff_output="${TXT_OUTPUT_DIR}/${app_name}-diff.txt"
	echo "ArgoCD Diff for ${app_name}" >"${diff_output}"
	echo "===========================================" >>"${diff_output}"
	echo "" >>"${diff_output}"

	# Check if app exists in cluster
	if argocd app get "${app_name}" --grpc-web &>/dev/null; then
		echo "App exists in cluster, running diff..." | tee -a "${diff_output}"
		echo "" >>"${diff_output}"

		# Run the diff (capture exit code to handle diffs gracefully)
		if argocd app diff "${app_name}" --grpc-web --local "${REPO_ROOT}/${path}" \
			--revision "${target_revision}" &>>"${diff_output}"; then
			echo "No differences detected" | tee -a "${diff_output}"
		else
			diff_exit=$?
			if [ ${diff_exit} -eq 1 ]; then
				echo "Differences detected (see above)" | tee -a "${diff_output}"
			else
				echo "Diff failed with exit code ${diff_exit}" | tee -a "${diff_output}"
			fi
		fi
	else
		echo "App does not exist in cluster yet (new application)" | tee -a "${diff_output}"
		echo "" >>"${diff_output}"

		# For new apps, just render with argocd to show what would be deployed
		echo "Rendering manifests for new application..." | tee -a "${diff_output}"
		echo "" >>"${diff_output}"

		# Use kubectl diff dry-run to simulate what would be deployed
		# This is a fallback when the app doesn't exist yet
		if argocd app manifests "${app_name}" --grpc-web --local "${REPO_ROOT}/${path}" \
			--revision "${target_revision}" &>>"${diff_output}"; then
			echo "Manifests rendered successfully" | tee -a "${diff_output}"
		else
			echo "Failed to render manifests" | tee -a "${diff_output}"
		fi
	fi

	rm -f "${app_yaml}"
	echo "::endgroup::"
done

echo "::notice::ArgoCD render and diff complete. Outputs saved to ${TXT_OUTPUT_DIR}"
