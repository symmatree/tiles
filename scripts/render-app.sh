#!/usr/bin/env bash
# Faithfully pre-render one app-of-apps child Application to static YAML, the way
# Argo CD would, but with the one genuinely-post-apply scalar (project_id) left as
# a collision-proof sentinel token instead of a real value.
#
# The render is two-level, mirroring Argo:
#   1. helm-template the argocd-applications (app-of-apps) chart for a given
#      cluster, which produces every child Application manifest with its
#      valuesObject fully expanded (domainFilters, extraArgs, etc.).
#   2. pull the named child's spec.source.{path,helm} back out and helm-template
#      that chart with the same valueFiles + valuesObject.
#
# Everything that is a Terraform *input* (cluster_name, vault_name, ...) is baked
# in per cluster. The only Terraform *output* that reaches a manifest -- project_id
# -- is fed in as the sentinel @@TILES_PROJECT@@ so the committed artifact never
# holds a real, post-apply value and therefore can never lag Terraform.
#
# Usage: scripts/render-app.sh <app-name> <inputs-file> [real_project_id]
#
# <inputs-file> is a YAML of the per-cluster propagated values -- every Terraform
# *input* (cluster_name, vault_name, seed_project_id, CIDRs, nfs paths, ...) at
# its real value, and the one Terraform *output* that reaches a manifest,
# project_id, set to the sentinel @@TILES_PROJECT@@. In CI this file is produced
# by pulling misc-config from 1Password (exactly the bootstrap handoff) with
# project_id overwritten by the sentinel.
#
# The optional [real_project_id] overrides project_id with a real value; it exists
# only for the round-trip proof (render sentinel vs. render real, then diff).
set -euo pipefail

APP="${1:?app name required, e.g. external-dns}"
INPUTS="${2:?inputs file required (per-cluster values, project_id=@@TILES_PROJECT@@)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INPUTS="$(cd "$(dirname "${INPUTS}")" && pwd)/$(basename "${INPUTS}")"

# Export every input as an environment variable BEFORE sourcing helm-common: it
# builds `--set <var>=${var:-placeholder}` from the environment (the same handoff
# the bootstrap workflow uses), so exported inputs flow into the render and
# unspecified vars fall back to "placeholder". project_id carries the sentinel
# unless the caller overrides it (round-trip proof only).
# shellcheck disable=SC2016  # the yq expression below is literal, not a shell expansion
while IFS=$'\t' read -r k v; do
	[[ -n ${k} ]] && export "${k}=${v}"
done < <(yq -o=tsv 'to_entries | .[] | [.key, .value] | @tsv' "${INPUTS}")
[[ -n ${3:-} ]] && export "project_id=${3}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/helm-common.bash"
cd "${REPO_ROOT}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# 1. Render the app-of-apps for this cluster; set_flags carries the exported inputs.
# shellcheck disable=SC2154  # helm_template_args and set_flags come from helm-common.bash
helm template argocd-applications charts/argocd-applications \
	--namespace argocd --skip-crds \
	"${helm_template_args[@]}" \
	"${set_flags[@]}" \
	>"${work}/app-of-apps.yaml"

# 2. Extract the named child Application's source path + helm block.
export APP
path="$(yq eval-all 'select(.kind == "Application" and .metadata.name == env(APP)) | .spec.source.path' "${work}/app-of-apps.yaml")"
if [[ -z ${path} || ${path} == "null" ]]; then
	echo "ERROR: no Application named '${APP}' with a single .spec.source.path in the app-of-apps render" >&2
	echo "(multi-source apps and tanka/plugin apps are rendered differently; this spike covers single-source helm apps)" >&2
	exit 1
fi

# valueFiles are repo-relative (they use values.yaml alongside the chart, and
# occasionally $values/... refs which we skip -- those resolve inside Argo only).
# shellcheck disable=SC2016  # yq expression and the grep pattern are literal, not shell
mapfile -t value_files < <(yq eval-all \
	'select(.kind == "Application" and .metadata.name == env(APP)) | .spec.source.helm.valueFiles[]' \
	"${work}/app-of-apps.yaml" 2>/dev/null | grep -v '^\$values' || true)

yq eval-all \
	'select(.kind == "Application" and .metadata.name == env(APP)) | .spec.source.helm.valuesObject' \
	"${work}/app-of-apps.yaml" >"${work}/values-object.yaml"

# 3. Render the child chart exactly as Argo would: its own valueFiles first, then
#    the Application's valuesObject last (highest precedence), matching Argo order.
helm_values_args=()
for vf in "${value_files[@]}"; do
	[[ -n ${vf} ]] && helm_values_args+=(-f "${path}/${vf}")
done
helm_values_args+=(-f "${work}/values-object.yaml")

helm template "${APP}" "${path}" \
	--namespace "${APP}" --skip-crds \
	"${helm_template_args[@]}" \
	"${helm_values_args[@]}"
