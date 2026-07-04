#!/bin/bash
# Sourced (not executed) by the Jupyter base image's run-hooks.sh for every
# *.sh in /usr/local/bin/before-notebook.d/, so this runs *in* start.sh's shell
# before the notebook server launches.
#
# The Dockerfile installs and `systemctl enable`s sshd, but the container has no
# init system (the entrypoint is the notebook start script), so the enabled unit
# never runs. Launch the daemon explicitly here. sshd forks to the background by
# default, so this returns immediately and the notebook server starts normally.
#
# Because we're sourced, keep all strictness inside a subshell: `set -u` at the
# top level would leak into start.sh, whose own `set -e` plus its reference to an
# unset JUPYTER_DOCKER_STACKS_QUIET then aborts container startup. The trailing
# `|| ...` keeps a broken sshd from taking the whole notebook down — it logs and
# lets the notebook come up without SSH rather than crashlooping the pod.
(
	set -euo pipefail

	# Host keys are generated at build time; regenerate any that are missing (e.g.
	# if /etc/ssh was overlaid) so sshd can start.
	ssh-keygen -A

	# sshd exits 255 with "Missing privilege separation directory: /run/sshd" if
	# the dir is absent. /run is a tmpfs that starts empty and no init system
	# creates it here, so make it ourselves.
	mkdir -p /run/sshd

	# The 1Password-managed key is mounted at /mnt/keys/authorized_keys, but its
	# secret-mount dir is world-writable (1777) so sshd's StrictModes refuses to
	# read authorized_keys from there. Copy it to the root-owned path sshd is
	# configured to trust (AuthorizedKeysFile in sshd_config). This hook runs as
	# root during start.sh setup, before the drop to jovyan.
	install -m 0644 /mnt/keys/authorized_keys /etc/ssh/authorized_keys

	/usr/sbin/sshd
) || echo "start-sshd.sh: WARNING: sshd failed to start; notebook continues without SSH" >&2
