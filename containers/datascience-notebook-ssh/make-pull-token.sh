#! /usr/bin/env bash
# One-time bootstrap: populate the .dockerconfigjson field on the
# jupyterhub-github-token item in 1Password so the OnePasswordItem in
# charts/jupyterhub/templates/ghcr-pull-secret.yaml can create a
# kubernetes.io/dockerconfigjson pull secret.
#
# Run this once before deploying, then re-run whenever the PAT is rotated.
# The item must already exist in 1Password with username/password/email fields.
set -euo pipefail
pushd "$(dirname "$0")"
SCRIPT_DIR=$(pwd)

VAULT=tiles-secrets
ITEM=jupyterhub-github-token
CURR_JSON=$(op item get --vault "$VAULT" "$ITEM" --format json)
SECRET=$(echo "$CURR_JSON" | jq -f "$SCRIPT_DIR/image-pull-secret.jq")
op item edit --vault "$VAULT" "$ITEM" "\\.dockerconfigjson=$SECRET"
