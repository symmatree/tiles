#!/usr/bin/env bash
# Proof that the pre-render + sentinel-swap compromise is lossless: for each app,
# render once with project_id as the sentinel, sed the sentinel back to a real
# value, and show that equals a direct render with the real value. If they differ,
# the "project_id is a pure leaf scalar" assumption leaked somewhere -- and this
# fails loudly instead of shipping a wrong manifest.
#
# Usage: scripts/prove-roundtrip.sh [inputs-file] [app...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

INPUTS="${1:-docs/prerender-spike/example-inputs.yaml}"
shift || true
APPS=("$@")
[[ ${#APPS[@]} -eq 0 ]] && APPS=(external-dns cert-manager)

SENTINEL="@@TILES_PROJECT@@"
REAL="roundtrip-proof-value"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

rc=0
for app in "${APPS[@]}"; do
	bash scripts/render-app.sh "${app}" "${INPUTS}" >"${tmp}/sentinel.yaml" 2>/dev/null
	sed "s/${SENTINEL}/${REAL}/g" "${tmp}/sentinel.yaml" >"${tmp}/reconstructed.yaml"
	bash scripts/render-app.sh "${app}" "${INPUTS}" "${REAL}" >"${tmp}/direct.yaml" 2>/dev/null

	n=$(grep -c "${SENTINEL}" "${tmp}/sentinel.yaml" || true)
	if diff -q "${tmp}/direct.yaml" "${tmp}/reconstructed.yaml" >/dev/null; then
		printf 'PASS  %-16s sentinel(sed)->real == direct-render   (sentinels=%s)\n' "${app}" "${n}"
	else
		printf 'FAIL  %-16s round-trip differs:\n' "${app}"
		diff "${tmp}/direct.yaml" "${tmp}/reconstructed.yaml" | sed 's/^/      /'
		rc=1
	fi
done
exit "${rc}"
