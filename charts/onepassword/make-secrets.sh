#!/usr/bin/env bash
set -euo pipefail

# We have to create ourselves for the initial secrets.
if ! kubectl get namespace onepassword; then
	kubectl create namespace onepassword &&
		kubectl label namespace onepassword pod-security.kubernetes.io/warn=baseline
fi

if ! kubectl get secret onepassword-token -n onepassword; then
	kubectl create secret generic -n onepassword \
		onepassword-token \
		"--from-literal=token=${onepassword_operator_token:?}"
fi

if ! kubectl get secret op-credentials -n onepassword; then
	# Connect mounts this secret key as a file (OP_SESSION). Kubernetes decodes the
	# secret once; the file must be raw JSON, not base64 of JSON. Older chart/env
	# setups sometimes expected an extra base64 layer; connect-helm-charts 2.4.x does not.

	# Read in separate assignment so we bail on errors.
	CREDS="${onepassword_connect_credentials:?}"
	echo "::add-mask::${CREDS}"
	kubectl create secret generic -n onepassword \
		op-credentials \
		"--from-literal=1password-credentials.json=${CREDS}"
fi
