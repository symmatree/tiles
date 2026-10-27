#!/bin/bash
set -euo pipefail

# Render every Argo CD Application the app-of-apps declares for one cluster, offline,
# the way Argo CD would: first the argocd-applications chart with the real propagated
# values, then each child Application from the source that render names.
#
#   scripts/render-apps.sh <cluster_name> <outdir> [repo_root]
#
# Writes <outdir>/<app>.yaml per Application (or <app>.ERROR with the renderer's
# stderr), plus argocd-applications.yaml and argocd-applications-installer.yaml for
# the two roots. Exits non-zero if any render failed, after rendering the rest.
#
# A change to an Application's app_settings in charts/argocd-applications shows up
# here as a change in the child's rendered manifests, which is what the two-stage
# render is for. See docs/render-diff.md.
#
# Needs helm, yq (mikefarah), tk and jb; network for charts pulled from a repo.

cluster="${1:?cluster_name is required}"
outdir="${2:?outdir is required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${3:-${SCRIPT_DIR}/..}" && pwd)"
mkdir -p "${outdir}"
outdir="$(cd "${outdir}" && pwd)"

# ---- the propagated value set --------------------------------------------------------
#
# Terraform passes module.cluster.app_of_apps_values (tf/modules/talos-cluster/main.tf)
# into the installer chart. Those are tf/nodes variables, so read them from the same
# tfvars Terraform does. The keys come from the installer's values.yaml, which is the
# declared set; a key with no mapping here fails the render rather than rendering a
# placeholder.
case "${cluster}" in
tiles) env_tfvars="prod" ;;
tiles-test) env_tfvars="test" ;;
*)
	echo "unknown cluster ${cluster}: expected tiles or tiles-test" >&2
	exit 2
	;;
esac
tfvars_files=("${REPO_ROOT}/tf/nodes/terraform.tfvars" "${REPO_ROOT}/tf/nodes/${env_tfvars}.tfvars")

# tfvar <name>: the string value of a scalar tfvars assignment, last file wins, falling
# back to the variable's default in variables.tf. Only quoted scalars are propagated.
tfvar() {
	local name="$1" value="" found=0 f got
	for f in "${tfvars_files[@]}"; do
		got=$(sed -nE "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$f" | tail -1 || true)
		if grep -qE "^[[:space:]]*${name}[[:space:]]*=" "$f"; then
			value="${got}"
			found=1
		fi
	done
	if [[ ${found} -eq 0 ]]; then
		got=$(awk -v v="${name}" '
			$1 == "variable" && $2 == "\"" v "\"" { inblock = 1 }
			inblock && $1 == "default" { sub(/^[^=]*=[[:space:]]*"/, ""); sub(/".*$/, ""); print; exit }
			inblock && /^}/ { exit }
		' "${REPO_ROOT}/tf/nodes/variables.tf")
		if [[ -z ${got} ]] && ! grep -qE 'default[[:space:]]*=[[:space:]]*""' <(awk -v v="${name}" '$1=="variable" && $2=="\"" v "\"" {p=1} p; p && /^}/ {exit}' "${REPO_ROOT}/tf/nodes/variables.tf"); then
			echo "no tfvars value or default for ${name}" >&2
			return 1
		fi
		value="${got}"
	fi
	printf '%s' "${value}"
}

set_flags=()
while IFS= read -r key; do
	[[ -z ${key} ]] && continue
	case "${key}" in
	cluster_name) value="${cluster}" ;;
	targetRevision) [[ ${cluster} == tiles ]] && value="prod" || value="test" ;;
	vault_name) value=$(tfvar onepassword_vault_name) ;;
	*) value=$(tfvar "${key}") ;;
	esac
	set_flags+=(--set-string "${key}=${value}")
done < <(grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' "${REPO_ROOT}/charts/argocd-applications-installer/values.yaml" | cut -d: -f1 | sort -u)

# ---- helm arguments shared with build.sh -------------------------------------------
helm_template_args=()
while IFS= read -r api_version; do
	[[ -z ${api_version} ]] && continue
	helm_template_args+=(-a "${api_version}")
done <"${REPO_ROOT}/charts/extract-apis/helm-api-versions.txt"
helm_template_args+=(--kube-version "$(tr -d '[:space:]' <"${REPO_ROOT}/charts/extract-apis/helm-kube-version.txt")")

# ---- stage one: the roots ------------------------------------------------------------
helm template argocd-applications-installer "${REPO_ROOT}/charts/argocd-applications-installer" \
	--namespace argocd --skip-crds "${helm_template_args[@]}" "${set_flags[@]}" \
	>"${outdir}/argocd-applications-installer.yaml"
helm template argocd-applications "${REPO_ROOT}/charts/argocd-applications" \
	--namespace argocd --skip-crds "${helm_template_args[@]}" "${set_flags[@]}" \
	>"${outdir}/argocd-applications.yaml"

# ---- stage two: each child, from its rendered Application --------------------------
# Tanka's CMP runs jb install before tk show; do the same once.
(cd "${REPO_ROOT}/tanka" && jb install >/dev/null 2>&1) || {
	echo "jb install failed in ${REPO_ROOT}/tanka" >&2
	exit 1
}

failed=0
app_yaml=$(mktemp)
values_yaml=$(mktemp)
trap 'rm -f "${app_yaml}" "${values_yaml}"' EXIT

render_one() {
	# Prints the manifests for the Application in ${app_yaml} to stdout.
	local src repo_url path chart revision namespace
	src=$(yq '(.spec.sources // [.spec.source]) | map(select(.ref == null))' "${app_yaml}")
	if [[ $(yq 'length' <<<"${src}") -ne 1 ]]; then
		echo "expected exactly one non-ref source" >&2
		return 1
	fi
	src=$(yq '.[0]' <<<"${src}")
	repo_url=$(yq '.repoURL' <<<"${src}")
	path=$(yq '.path // ""' <<<"${src}")
	chart=$(yq '.chart // ""' <<<"${src}")
	revision=$(yq '.targetRevision' <<<"${src}")
	namespace=$(yq '.spec.destination.namespace' "${app_yaml}")

	for unsupported in .helm.parameters .helm.values .helm.fileParameters .kustomize .directory; do
		if [[ $(yq "${unsupported}" <<<"${src}") != null ]]; then
			echo "${unsupported} is not supported by this renderer" >&2
			return 1
		fi
	done

	if [[ $(yq '.plugin' <<<"${src}") != null ]]; then
		# Tanka through the CMP: charts/argocd/templates/tanka.yaml generate.sh.
		local tk_env params
		tk_env=$(yq '.plugin.env[] | select(.name == "TK_ENV") | .value' <<<"${src}")
		params=$(yq -o=json -I=0 '.plugin.parameters' <<<"${src}")
		(cd "${REPO_ROOT}/${path}" && tk show "environments/${tk_env}" --dangerous-allow-redirect \
			--ext-str ARGOCD_APP_PARAMETERS="${params}")
		return
	fi

	local -a helm_args=(--namespace "${namespace}" "${helm_template_args[@]}")
	if [[ $(yq '.helm.skipCrds // false' <<<"${src}") == true ]]; then
		helm_args+=(--skip-crds)
	else
		helm_args+=(--include-crds)
	fi
	local vf
	while IFS= read -r vf; do
		[[ -z ${vf} ]] && continue
		if [[ ${vf} == \$values/* ]]; then
			helm_args+=(-f "${REPO_ROOT}/${vf#\$values/}")
		else
			helm_args+=(-f "${REPO_ROOT}/${path}/${vf}")
		fi
	done < <(yq '.helm.valueFiles // [] | .[]' <<<"${src}")
	if [[ $(yq '.helm.valuesObject' <<<"${src}") != null ]]; then
		yq '.helm.valuesObject' <<<"${src}" >"${values_yaml}"
		helm_args+=(-f "${values_yaml}")
	fi

	local release
	release=$(yq '.helm.releaseName // ""' <<<"${src}")
	[[ -z ${release} ]] && release=$(yq '.metadata.name' "${app_yaml}")

	if [[ -n ${chart} ]]; then
		if [[ ${repo_url} == oci://* ]]; then
			helm template "${release}" "${repo_url}/${chart}" --version "${revision}" "${helm_args[@]}"
		else
			helm template "${release}" "${chart}" --repo "${repo_url}" --version "${revision}" "${helm_args[@]}"
		fi
	else
		# Subchart archives are not committed; fetch what Chart.lock pins, as Argo CD does.
		if [[ -f ${REPO_ROOT}/${path}/Chart.lock ]]; then
			helm dependency build "${REPO_ROOT}/${path}" >/dev/null
		fi
		helm template "${release}" "${REPO_ROOT}/${path}" "${helm_args[@]}"
	fi
}

while IFS= read -r app; do
	[[ -z ${app} ]] && continue
	yq "select(.kind == \"Application\" and .metadata.name == \"${app}\")" "${outdir}/argocd-applications.yaml" >"${app_yaml}"
	rm -f "${outdir}/${app}.yaml" "${outdir}/${app}.ERROR"
	if render_one >"${outdir}/${app}.yaml" 2>"${outdir}/${app}.ERROR"; then
		rm -f "${outdir}/${app}.ERROR"
	else
		echo "render failed: ${app} (see ${outdir}/${app}.ERROR)" >&2
		rm -f "${outdir}/${app}.yaml"
		failed=1
	fi
done < <(yq -N 'select(.kind == "Application") | .metadata.name' "${outdir}/argocd-applications.yaml" | sort -u)

exit "${failed}"
