#!/bin/bash
set -euo pipefail

# Diff what Argo CD would deploy before and after a change: render every Application
# (scripts/render-apps.sh) from the merge base and from the working tree, then diff
# them per app and per cluster.
#
#   scripts/render-apps-diff.sh [base_ref]
#
#   base_ref         what to compare against; default origin/main. The base is
#                    git merge-base HEAD <base_ref>, so a PR branch diffs against the
#                    main it forked from, not main's tip.
#   TXT_OUTPUT_DIR   where render-diff-<cluster>.txt land; default /tmp/txt-outputs.
#                    One file per cluster, summary first, then unified diffs. The
#                    PR-comment action picks up every .txt there.
#   CLUSTERS         default "tiles tiles-test".
#
# The working tree is rendered as it is, uncommitted edits included, so this is also
# the local render-diff-before-commit. Both sides render with THIS tree's render-apps.sh,
# so a change to the renderer shows the apps it affects rather than a diff of itself.
# See docs/render-diff.md.

base_ref="${1:-origin/main}"
TXT_OUTPUT_DIR="${TXT_OUTPUT_DIR:-/tmp/txt-outputs}"
CLUSTERS="${CLUSTERS:-tiles tiles-test}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
mkdir -p "${TXT_OUTPUT_DIR}"

base_sha=$(git -C "${REPO_ROOT}" merge-base HEAD "${base_ref}")
work=$(mktemp -d)
cleanup() {
	git -C "${REPO_ROOT}" worktree remove --force "${work}/base" 2>/dev/null || true
	rm -rf "${work}"
}
trap cleanup EXIT
git -C "${REPO_ROOT}" worktree add --detach --quiet "${work}/base" "${base_sha}"
echo "base: ${base_sha} ($(git -C "${REPO_ROOT}" log -1 --format=%s "${base_sha}"))"

changed_total=0
for cluster in ${CLUSTERS}; do
	echo "::group::render ${cluster}"
	# A failed render leaves <app>.ERROR in place of <app>.yaml, which the diff then shows.
	"${SCRIPT_DIR}/render-apps.sh" "${cluster}" "${work}/out/base/${cluster}" "${work}/base" || true
	"${SCRIPT_DIR}/render-apps.sh" "${cluster}" "${work}/out/head/${cluster}" "${REPO_ROOT}" || true
	echo "::endgroup::"

	out="${TXT_OUTPUT_DIR}/render-diff-${cluster}.txt"
	summary=$(mktemp)
	detail=$(mktemp)
	changed=0
	while IFS= read -r f; do
		base_file="${work}/out/base/${cluster}/${f}"
		head_file="${work}/out/head/${cluster}/${f}"
		if cmp -s "${base_file}" "${head_file}" 2>/dev/null; then
			continue
		fi
		changed=$((changed + 1))
		if [[ ! -e ${base_file} ]]; then
			state="added"
		elif [[ ! -e ${head_file} ]]; then
			state="removed"
		else
			state="changed"
		fi
		set +e
		d=$(diff -u --label "base/${f}" --label "head/${f}" "${base_file}" "${head_file}" 2>/dev/null)
		set -e
		if [[ ! -e ${base_file} ]]; then
			d=$(diff -u --label /dev/null --label "head/${f}" /dev/null "${head_file}" || true)
		elif [[ ! -e ${head_file} ]]; then
			d=$(diff -u --label "base/${f}" --label /dev/null "${base_file}" /dev/null || true)
		fi
		plus=$(grep -c '^+[^+]' <<<"${d}" || true)
		minus=$(grep -c '^-[^-]' <<<"${d}" || true)
		printf '  %-40s %-8s +%s -%s\n' "${f}" "${state}" "${plus}" "${minus}" >>"${summary}"
		printf '\n==== %s (%s)\n%s\n' "${f}" "${state}" "${d}" >>"${detail}"
	done < <(
		{
			(cd "${work}/out/base/${cluster}" 2>/dev/null && ls) || true
			(cd "${work}/out/head/${cluster}" 2>/dev/null && ls) || true
		} | sort -u
	)

	{
		echo "Rendered diff for ${cluster} against ${base_sha:0:12}"
		if [[ ${changed} -eq 0 ]]; then
			echo "No rendered changes."
		else
			echo "${changed} file(s) differ:"
			cat "${summary}"
			cat "${detail}"
		fi
	} >"${out}"
	rm -f "${summary}" "${detail}"
	changed_total=$((changed_total + changed))
	echo "${cluster}: ${changed} file(s) differ -> ${out}"
done

echo "total: ${changed_total} file(s) differ"
