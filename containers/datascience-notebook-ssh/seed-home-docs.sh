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
