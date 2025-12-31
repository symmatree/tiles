#!/bin/bash
set -euo pipefail

# This script applies Talos configuration after Terraform has created the VMs.
# It should be run after terraform apply, with environment variables loaded from
# 1Password misc-config (via 1password/load-secrets-action).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install required tools if not present
install_tools() {
	# Check and install talosctl
	if ! command -v talosctl &>/dev/null; then
		echo "Installing talosctl..."
		curl -Lo /tmp/talosctl "https://github.com/siderolabs/talos/releases/latest/download/talosctl-linux-amd64"
		chmod +x /tmp/talosctl
		sudo mv /tmp/talosctl /usr/local/bin/talosctl
		echo "Installed talosctl $(talosctl version --short)"
	else
		echo "talosctl already installed: $(talosctl version --short)"
	fi

	# Check and install 1Password CLI
	if ! command -v op &>/dev/null; then
		echo "Installing 1Password CLI..."
		# Add 1Password repository
		curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
		echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64/stable main' | sudo tee /etc/apt/sources.list.d/1password.list
		sudo apt-get update
		sudo apt-get install -y 1password-cli
		echo "Installed 1Password CLI"
	else
		echo "1Password CLI already installed: $(op --version)"
	fi

	# Check for envsubst (usually in gettext package)
	if ! command -v envsubst &>/dev/null; then
		echo "Installing envsubst (gettext)..."
		sudo apt-get update
		sudo apt-get install -y gettext-base
	fi
}

echo "::group::Install required tools"
install_tools
echo "::endgroup::"

# Required environment variables (should be loaded from 1Password misc-config)
required_vars=(
	"cluster_name"
	"pod_cidr"
	"service_cidr"
	"control_plane_vip"
	"control_plane_vip_link"
	"talos_install_image"
	"control_plane_ips"
	"bootstrap_ip"
	"vault_name"
)
# worker_ips is optional (may be empty if no workers)

# Validate required variables
missing_vars=()
for var in "${required_vars[@]}"; do
	if [[ -z ${!var:-} ]]; then
		missing_vars+=("$var")
	fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
	echo "Error: Missing required environment variables:" >&2
	printf "  - %s\n" "${missing_vars[@]}" >&2
	echo "These should be loaded from 1Password misc-config." >&2
	exit 1
fi

# Parse control plane IPs (comma-separated)
IFS=',' read -ra CONTROL_PLANE_IPS_ARRAY <<<"${control_plane_ips:-}"

echo "::group::Load or generate Talos secrets"
# Check if secrets already exist in 1Password - reuse them to avoid breaking the cluster
# CRITICAL: Never regenerate secrets for an existing cluster - it will break everything
SECRETS_FILE="${SCRIPT_DIR}/secrets.yaml"
if op item get "${cluster_name:-}-machine-secrets" --vault "${vault_name:-}" --fields notesPlain >"$SECRETS_FILE" 2>/dev/null; then
	echo "Reusing existing machine secrets from 1Password (idempotent)"
	touch "${SCRIPT_DIR}/.secrets_reused"
else
	echo "No existing secrets found, generating new ones (first-time setup)"
	talosctl gen secrets "$SECRETS_FILE"
	rm -f "${SCRIPT_DIR}/.secrets_reused"
fi
echo "::endgroup::"

echo "::group::Generate Talos machine configurations"
# Generate configs with patches
talosctl gen config "${cluster_name:-}" "https://${control_plane_vip:-}:6443" \
	--with-secrets "$SECRETS_FILE" \
	--config-patch "@${SCRIPT_DIR}/talos-config.yaml" \
	--config-patch-control-plane <(envsubst <"${SCRIPT_DIR}/common-patch.yaml.tmpl") \
	--config-patch-control-plane <(envsubst <"${SCRIPT_DIR}/layer2-vip-config.yaml.tmpl") \
	--config-patch-worker <(envsubst <"${SCRIPT_DIR}/common-patch.yaml.tmpl") \
	--with-docs=false \
	--with-examples=false

echo "Generated controlplane.yaml and worker.yaml"
echo "::endgroup::"

echo "::group::Apply machine configurations to control plane nodes"
for node_ip in "${CONTROL_PLANE_IPS_ARRAY[@]}"; do
	echo "Applying config to control plane node: $node_ip"
	talosctl apply-config \
		--insecure \
		--nodes "$node_ip" \
		--file controlplane.yaml
done
echo "::endgroup::"

echo "::group::Apply machine configurations to worker nodes"
if [[ -n ${worker_ips:-} ]]; then
	IFS=',' read -ra WORKER_IPS_ARRAY <<<"$worker_ips"
	for node_ip in "${WORKER_IPS_ARRAY[@]}"; do
		if [[ -n $node_ip ]]; then
			echo "Applying config to worker node: $node_ip"
			talosctl apply-config \
				--insecure \
				--nodes "$node_ip" \
				--file worker.yaml
		fi
	done
else
	echo "No worker nodes to configure"
fi
echo "::endgroup::"

echo "::group::Bootstrap cluster and get kubeconfig"
# Bootstrap is idempotent - talosctl bootstrap will only bootstrap if not already bootstrapped
# It's safe to call multiple times
talosctl bootstrap \
	--nodes "${bootstrap_ip:-}" \
	--talosconfig talosconfig

# Get kubeconfig (also idempotent - regenerates but doesn't break anything)
talosctl kubeconfig \
	--nodes "${bootstrap_ip:-}" \
	--talosconfig talosconfig
echo "::endgroup::"

echo "::group::Store secrets in 1Password"
# Store machine secrets (only if we generated new ones)
if [[ ! -f "${SCRIPT_DIR}/.secrets_reused" ]]; then
	op item edit \
		--vault "$vault_name" \
		"${cluster_name}-machine-secrets" \
		"notesPlain=$(cat "$SECRETS_FILE")" \
		2>/dev/null || op item create \
		--vault "$vault_name" \
		--category "Secure Note" \
		--title "${cluster_name}-machine-secrets" \
		"notesPlain=$(cat "$SECRETS_FILE")"
	echo "Stored machine secrets in 1Password"
else
	echo "Skipping machine secrets storage (reused existing)"
fi

# Store talosconfig
op item edit \
	--vault "$vault_name" \
	"${cluster_name}-talosconfig" \
	"notesPlain=$(cat talosconfig)" \
	2>/dev/null || op item create \
	--vault "$vault_name" \
	--category "Secure Note" \
	--title "${cluster_name}-talosconfig" \
	"notesPlain=$(cat talosconfig)"

# Store kubeconfig
op item edit \
	--vault "$vault_name" \
	"${cluster_name}-kubeconfig" \
	"notesPlain=$(cat kubeconfig)" \
	2>/dev/null || op item create \
	--vault "$vault_name" \
	--category "Secure Note" \
	--title "${cluster_name}-kubeconfig" \
	"notesPlain=$(cat kubeconfig)"

echo "Stored secrets in 1Password"
echo "::endgroup::"

# Cleanup
rm -f "${SCRIPT_DIR}/secrets.yaml" "${SCRIPT_DIR}/.secrets_reused" controlplane.yaml worker.yaml talosconfig kubeconfig

echo "Talos configuration applied successfully"
