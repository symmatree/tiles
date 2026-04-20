#!/usr/bin/env bash
set -euo pipefail
pushd "$(dirname "$0")"
SCRIPT_DIR=$(pwd)

# Update the dockerconfigjson field on the 1Password item from its own
# username/password/email fields, so the 1Password operator can create
# a kubernetes.io/dockerconfigjson secret from it.
VAULT=${VAULT:-tiles-secrets}
ITEM=jupyterhub-github-token
CURR_JSON=$(op item get --vault "$VAULT" "$ITEM" --format json)
SECRET=$(echo "$CURR_JSON" | jq -f "$SCRIPT_DIR/image-pull-secret.jq")
op item edit --vault "$VAULT" "$ITEM" "\\.dockerconfigjson=$SECRET"
