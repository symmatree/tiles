#!/bin/bash
# Seed home-directory docs into the user's home.
#
# /home/${NB_USER} is an NFS mount that masks anything baked into the image at
# that path, so the docs are staged at /opt/home-skel and copied in here. The
# Jupyter base image runs every executable in before-notebook.d/ on each start,
# so this refreshes the copy every time -- the doc always matches the running
# image. Edit the source in the repo, not the copy in the home dir.
#
# Best-effort: a failure here must never stop the notebook from starting.
#
# Because we're sourced (not executed), keep all strictness inside a subshell:
# `set -u` at the top level would leak into start.sh, whose own `set -e` plus its
# reference to an unset JUPYTER_DOCKER_STACKS_QUIET then aborts container startup.
# (This hook sorts before start-sshd.sh, so it is the first to trip that.)
(
	set -euo pipefail

	dest="/home/${NB_USER:-jovyan}"
	src="/opt/home-skel/AGENTS.md"

	if [ -d "${dest}" ] && [ -f "${src}" ]; then
		if cp -f "${src}" "${dest}/AGENTS.md"; then
			echo "seed-home-docs.sh: refreshed ${dest}/AGENTS.md"
		else
			echo "seed-home-docs.sh: WARNING: failed to seed AGENTS.md; continuing" >&2
		fi
	fi
) || echo "seed-home-docs.sh: WARNING: failed to seed home docs; notebook continues" >&2
