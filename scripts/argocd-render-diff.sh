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
	curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
	chmod +x /tmp/argocd
	sudo mv /tmp/argocd /usr/local/bin/argocd
	echo "ArgoCD CLI installed: $(argocd version --client)"
else
	echo "ArgoCD CLI already installed: $(argocd version --client)"
fi
echo "::endgroup::"

echo "::group::Login to ArgoCD"
# Login to argocd using kubectl port-forward (works better in CI)
# Start port-forward in background
kubectl port-forward -n argocd svc/argocd-server 8080:443 &
PORT_FORWARD_PID=$!
echo "Port-forward PID: ${PORT_FORWARD_PID}"

# Wait for port-forward to be ready
echo "Waiting for port-forward to be ready..."
for i in {1..30}; do
	if curl -k -s https://localhost:8080 >/dev/null 2>&1; then
		echo "Port-forward is ready"
		break
	fi
	if [ $i -eq 30 ]; then
		echo "::error::Port-forward failed to become ready"
		kill "${PORT_FORWARD_PID}" 2>/dev/null || true
		exit 1
	fi
	sleep 1
done

# Login using kubernetes auth (no password needed)
argocd login localhost:8080 --core --insecure
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
	has_plugin=$(yq eval '.spec.source.plugin // "null"' "${app_yaml}")

	echo "Application: ${app_name}"
	echo "  Repo: ${repo_url}"
	echo "  Revision: ${target_revision}"
	echo "  Path: ${path}"
	echo "  Namespace: ${namespace}"
	echo "  Plugin: ${has_plugin}"

	# Try to diff against live cluster
	diff_output="${TXT_OUTPUT_DIR}/${app_name}-diff.txt"
	echo "ArgoCD Diff for ${app_name}" >"${diff_output}"
	echo "===========================================" >>"${diff_output}"
	echo "" >>"${diff_output}"

	# Skip plugin-based applications for now
	if [ "${has_plugin}" != "null" ]; then
		echo "Skipping plugin-based application (Tanka/other) - not supported yet" | tee -a "${diff_output}"
		rm -f "${app_yaml}"
		echo "::endgroup::"
		continue
	fi

	# Check if app exists in cluster
	if argocd app get "${app_name}" &>/dev/null; then
		echo "App exists in cluster, running diff..." | tee -a "${diff_output}"
		echo "" >>"${diff_output}"

		# Run the diff (capture exit code to handle diffs gracefully)
		# Note: argocd app diff returns 1 if there are differences, which is expected
		set +e
		argocd app diff "${app_name}" --local "${REPO_ROOT}/${path}" \
			--revision "${target_revision}" >>"${diff_output}" 2>&1
		diff_exit=$?
		set -e

		if [ ${diff_exit} -eq 0 ]; then
			echo "No differences detected" | tee -a "${diff_output}"
		elif [ ${diff_exit} -eq 1 ]; then
			echo "Differences detected (see above)" | tee -a "${diff_output}"
		else
			echo "Diff failed with exit code ${diff_exit}" | tee -a "${diff_output}"
		fi
	else
		echo "App does not exist in cluster yet (new application)" | tee -a "${diff_output}"
		echo "" >>"${diff_output}"

		# For new apps, render the manifests to show what would be deployed
		echo "Rendering manifests for new application..." | tee -a "${diff_output}"
		echo "" >>"${diff_output}"

		# Try to render manifests using helm template directly
		cd "${REPO_ROOT}/${path}"
		if [ -f "Chart.yaml" ]; then
			# It's a Helm chart
			helm template "${app_name}" . --namespace "${namespace}" \
				--skip-crds \
				"${helm_template_args[@]}" \
				"${set_flags[@]}" >>"${diff_output}" 2>&1 || echo "Failed to render Helm chart" | tee -a "${diff_output}"
		else
			echo "Not a Helm chart, skipping manifest rendering" | tee -a "${diff_output}"
		fi
	fi

	rm -f "${app_yaml}"
	echo "::endgroup::"
done

# Cleanup port-forward if it was started
if [ -n "${PORT_FORWARD_PID:-}" ]; then
	echo "Stopping port-forward (PID: ${PORT_FORWARD_PID})..."
	kill "${PORT_FORWARD_PID}" 2>/dev/null || true
	# Wait for process to terminate (up to 5 seconds)
	for i in {1..5}; do
		if ! kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
			echo "Port-forward stopped"
			break
		fi
		sleep 1
	done
fi

echo "::notice::ArgoCD render and diff complete. Outputs saved to ${TXT_OUTPUT_DIR}"
