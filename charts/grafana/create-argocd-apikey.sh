#!/usr/bin/env bash
# Script to create a Grafana API key for ArgoCD notifications integration
# This script should be run after Grafana is deployed and accessible
set -euo pipefail

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://grafana.grafana.svc.cluster.local}"
VAULT_NAME="${vault_name:-}"

if [ -z "$VAULT_NAME" ]; then
  echo "ERROR: vault_name environment variable is required"
  exit 1
fi

echo "=== Grafana API Key Creator for ArgoCD Notifications ==="
echo ""
echo "This script will:"
echo "1. Create a Grafana Service Account for ArgoCD"
echo "2. Generate an API token for the service account"
echo "3. Store the token in 1Password for ArgoCD to retrieve"
echo ""

# Check if kubectl is available and connected
if ! kubectl get namespace grafana > /dev/null 2>&1; then
  echo "ERROR: Cannot access grafana namespace. Is kubectl configured correctly?"
  exit 1
fi

# Get Grafana admin credentials from the secret
echo "Retrieving Grafana admin credentials..."
ADMIN_USER=$(kubectl get secret grafana-admin-user -n grafana -o jsonpath='{.data.username}' | base64 -d)
ADMIN_PASS=$(kubectl get secret grafana-admin-user -n grafana -o jsonpath='{.data.password}' | base64 -d)

# Wait for Grafana to be ready (if running in-cluster)
echo "Checking if Grafana is ready..."
if ! kubectl get deployment -n grafana grafana > /dev/null 2>&1; then
  echo "WARNING: Grafana deployment not found. Make sure Grafana is deployed first."
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Port-forward to Grafana if not running in-cluster
if [ "$GRAFANA_URL" = "http://grafana.grafana.svc.cluster.local" ]; then
  echo "Setting up port-forward to Grafana..."
  kubectl port-forward -n grafana svc/grafana 3000:80 &
  PORT_FORWARD_PID=$!
  trap 'kill $PORT_FORWARD_PID 2>/dev/null || true' EXIT
  sleep 3
  GRAFANA_URL="http://localhost:3000"
fi

# Check Grafana is accessible
echo "Checking Grafana health..."
if ! curl -sf "${GRAFANA_URL}/api/health" > /dev/null; then
  echo "ERROR: Grafana is not accessible at ${GRAFANA_URL}"
  exit 1
fi

echo "Grafana is ready!"

# Create service account
echo "Creating service account 'argocd-notifications' in Grafana..."
SA_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -d '{"name":"argocd-notifications","role":"Editor"}' \
  "${GRAFANA_URL}/api/serviceaccounts")

SA_ID=$(echo "$SA_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

if [ -z "$SA_ID" ]; then
  echo "Service account may already exist, attempting to find it..."
  SA_LIST=$(curl -s -X GET \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${GRAFANA_URL}/api/serviceaccounts/search?query=argocd-notifications")
  SA_ID=$(echo "$SA_LIST" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
fi

if [ -z "$SA_ID" ]; then
  echo "ERROR: Could not create or find service account"
  echo "Response: $SA_RESPONSE"
  exit 1
fi

echo "Service account ID: $SA_ID"

# Create token
echo "Creating API token for service account..."
TOKEN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -d '{"name":"argocd-notifications-token"}' \
  "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens")

API_KEY=$(echo "$TOKEN_RESPONSE" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

if [ -z "$API_KEY" ]; then
  echo "ERROR: Could not create API key"
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi

echo "✓ API key created successfully!"
echo ""

# Store in 1Password using CLI
echo "Storing API key in 1Password..."
echo ""
echo "Creating 1Password item: grafana-argocd-apikey"

# Check if op CLI is available
if ! command -v op &> /dev/null; then
  echo "ERROR: 1Password CLI (op) is not installed"
  echo "Please install it from: https://developer.1password.com/docs/cli/get-started/"
  echo ""
  echo "The API key has been generated. You can manually store it in 1Password:"
  echo "  Vault: ${VAULT_NAME}"
  echo "  Item name: grafana-argocd-apikey"
  echo "  Field name: apikey"
  echo "  Field type: password/concealed"
  echo ""
  echo "API Key: ${API_KEY}"
  exit 1
fi

# Create or update the item in 1Password
# Using op CLI v2 syntax
if op item get "grafana-argocd-apikey" --vault "${VAULT_NAME}" &>/dev/null; then
  echo "Item exists, updating..."
  echo "${API_KEY}" | op item edit "grafana-argocd-apikey" \
    --vault "${VAULT_NAME}" \
    "apikey[password]=${API_KEY}"
else
  echo "Creating new item..."
  echo "${API_KEY}" | op item create \
    --category=password \
    --title="grafana-argocd-apikey" \
    --vault="${VAULT_NAME}" \
    "apikey[password]=${API_KEY}"
fi

echo ""
echo "✓ API key stored in 1Password successfully!"
echo ""
echo "Next steps:"
echo "1. Enable Grafana integration in ArgoCD by setting grafana_integration_enabled: true"
echo "2. Deploy the updated ArgoCD configuration"
echo "3. ArgoCD will automatically retrieve the API key from 1Password"
echo ""
echo "Done!"
