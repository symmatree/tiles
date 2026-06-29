#!/bin/bash
# Started by the Jupyter base image's start.sh, which runs every executable in
# /usr/local/bin/before-notebook.d/ before launching the notebook server.
#
# The Dockerfile installs and `systemctl enable`s sshd, but the container has no
# init system (the entrypoint is the notebook start script), so the enabled unit
# never runs. Launch the daemon explicitly here. sshd forks to the background by
# default, so this returns immediately and the notebook server starts normally.
set -euo pipefail

# Host keys are generated at build time; regenerate any that are missing (e.g.
# if /etc/ssh was overlaid) so sshd can start.
ssh-keygen -A

/usr/sbin/sshd
