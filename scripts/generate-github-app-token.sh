#!/usr/bin/env bash
# Script to generate GitHub App installation tokens and store them in 1Password
# This provides programmatic token generation for services like Grafana that need
# standalone tokens (not directly managed by Terraform).

set -euo pipefail

# Configuration
VAULT_NAME="${VAULT_NAME:-tiles-secrets}"
TOKEN_NAME="${TOKEN_NAME:-grafana-github-token}"
ORG_NAME="${ORG_NAME:-symmatree}"

# GitHub App credentials (from 1Password)
APP_ID="${GITHUB_APP_ID:-$(op read "op://${VAULT_NAME}/github-app-tiles-tf/app_details/app_id" 2>/dev/null || echo "")}"
INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-$(op read "op://${VAULT_NAME}/github-app-tiles-tf/app_details/installation_id" 2>/dev/null || echo "")}"
PEM_FILE="${GITHUB_APP_PEM_FILE:-$(op read "op://${VAULT_NAME}/github-app-tiles-tf/password" 2>/dev/null || echo "")}"

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Generate a GitHub App installation token and store it in 1Password.

Options:
    -h, --help              Show this help message
    -v, --vault NAME        1Password vault name (default: tiles-secrets)
    -t, --token-name NAME   Name for token in 1Password (default: grafana-github-token)
    -o, --org NAME          GitHub organization name (default: symmatree)

Environment Variables:
    GITHUB_APP_ID               GitHub App ID
    GITHUB_APP_INSTALLATION_ID  GitHub App Installation ID
    GITHUB_APP_PEM_FILE         GitHub App private key (PEM content)
    VAULT_NAME                  1Password vault name
    TOKEN_NAME                  Token name in 1Password
    ORG_NAME                    GitHub organization name

Example:
    # Using 1Password for app credentials
    $0

    # Using environment variables
    export GITHUB_APP_ID="123456"
    export GITHUB_APP_INSTALLATION_ID="78901234"
    export GITHUB_APP_PEM_FILE=$(cat /path/to/app.pem)
    $0 -t grafana-github-token

Requirements:
    - jq (for JSON processing)
    - openssl (for JWT generation)
    - op (1Password CLI) if fetching credentials from 1Password
    - curl (for API calls)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	-h | --help)
		usage
		exit 0
		;;
	-v | --vault)
		VAULT_NAME="$2"
		shift 2
		;;
	-t | --token-name)
		TOKEN_NAME="$2"
		shift 2
		;;
	-o | --org)
		ORG_NAME="$2"
		shift 2
		;;
	*)
		echo "Error: Unknown option $1"
		usage
		exit 1
		;;
	esac
done

# Check required tools
for cmd in jq openssl curl envsubst; do
	if ! command -v "$cmd" &>/dev/null; then
		echo "Error: Required command '$cmd' not found"
		exit 1
	fi
done

# Validate required variables
if [[ -z $APP_ID ]]; then
	echo "Error: GITHUB_APP_ID not provided"
	exit 1
fi

if [[ -z $INSTALLATION_ID ]]; then
	echo "Error: GITHUB_APP_INSTALLATION_ID not provided"
	exit 1
fi

if [[ -z $PEM_FILE ]]; then
	echo "Error: GITHUB_APP_PEM_FILE not provided"
	exit 1
fi

echo "Generating GitHub App installation token..."

# Generate JWT for GitHub App authentication
# JWT payload with standard claims
NOW=$(date +%s)
EXP=$((NOW + 600)) # 10 minutes from now (GitHub maximum)

# Create JWT header
JWT_HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

# Create JWT payload
JWT_PAYLOAD=$(jq -n \
	--arg iat "$NOW" \
	--arg exp "$EXP" \
	--arg iss "$APP_ID" \
	'{iat: ($iat | tonumber), exp: ($exp | tonumber), iss: $iss}' |
	openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

# Create JWT signature
TEMP_KEY_FILE=$(mktemp)
chmod 600 "$TEMP_KEY_FILE"
echo "$PEM_FILE" >"$TEMP_KEY_FILE"
JWT_SIGNATURE=$(echo -n "${JWT_HEADER}.${JWT_PAYLOAD}" |
	openssl dgst -sha256 -sign "$TEMP_KEY_FILE" |
	openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
rm -f "$TEMP_KEY_FILE"

# Complete JWT
JWT="${JWT_HEADER}.${JWT_PAYLOAD}.${JWT_SIGNATURE}"

echo "Requesting installation access token..."

# Get installation access token
RESPONSE=$(curl -s -X POST \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: Bearer ${JWT}" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens")

# Extract token from response
TOKEN=$(echo "$RESPONSE" | jq -r '.token')

if [[ $TOKEN == "null" ]] || [[ -z $TOKEN ]]; then
	echo "Error: Failed to get installation token"
	echo "Response: $RESPONSE"
	exit 1
fi

EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')
echo "Token generated successfully (expires at: $EXPIRES_AT)"

# Generate Grafana datasource.yaml configuration from template
# The datasource sidecar expects a Secret with a 'datasource.yaml' key
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../tf/modules/github-app-token/datasource.yaml.tpl"

if [[ ! -f $TEMPLATE_FILE ]]; then
	echo "Error: Template file not found: $TEMPLATE_FILE"
	exit 1
fi

# Substitute ${token} placeholder with actual token value using envsubst
export token="$TOKEN"
DATASOURCE_YAML=$(envsubst <"$TEMPLATE_FILE")

# Store in 1Password
echo "Storing token and datasource configuration in 1Password vault '${VAULT_NAME}' as '${TOKEN_NAME}'..."

if command -v op &>/dev/null; then
	# Check if item exists
	if op item get "${TOKEN_NAME}" --vault "${VAULT_NAME}" &>/dev/null; then
		echo "Updating existing item..."
		# Update username/password for build scripts, and add datasource.yaml field for Grafana
		op item edit --vault "${VAULT_NAME}" "${TOKEN_NAME}" \
			"password=${TOKEN}" \
			"username=${ORG_NAME}" \
			"datasource.yaml=${DATASOURCE_YAML}" >/dev/null
	else
		echo "Creating new item..."
		op item create \
			--vault "${VAULT_NAME}" \
			--category "password" \
			--title "${TOKEN_NAME}" \
			"username=${ORG_NAME}" \
			"password=${TOKEN}" \
			"datasource.yaml=${DATASOURCE_YAML}" \
			"metadata.source=github-app-token-generator" \
			"metadata.app_id=${APP_ID}" \
			"metadata.installation_id=${INSTALLATION_ID}" \
			"metadata.expires_at=${EXPIRES_AT}" \
			"metadata.generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
	fi

	echo "Token and datasource configuration stored successfully in 1Password!"
	echo ""
	echo "Note: This token expires in 1 hour. Re-run this script to generate a new token."
	echo ""
	echo "The item contains:"
	echo "  - username: ${ORG_NAME} (for build scripts)"
	echo "  - password: ${TOKEN} (for build scripts)"
	echo "  - datasource.yaml: Full Grafana datasource.yaml configuration"
else
	echo "Warning: 1Password CLI (op) not found. Token not stored."
	echo "Token: $TOKEN"
	echo "Expires: $EXPIRES_AT"
	echo ""
	echo "Datasource YAML:"
	echo "$DATASOURCE_YAML"
fi
