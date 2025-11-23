#!/usr/bin/env bash
set -euxo pipefail

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
	# thanks to https://www.1password.community/discussions/developers/loadlocalauthv2-failed-to-credentialsdatafrombase64/84597
	# and its pointer to https://github.com/1Password/connect-helm-charts/blob/main/charts/connect/templates/connect-credentials.yaml#L14
	# where the plaintext is base64 encoded before being put in the secret (probably due to misunderstanding).

	# Read in separate assignment so we bail on errors.
	JSON=${onepassword_connect_credentials:?}
	kubectl create secret generic -n onepassword \
		op-credentials \
		"--from-literal=1password-credentials.json=$(echo "$JSON" | base64)"
fi
