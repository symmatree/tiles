ARG BASE_IMAGE=quay.io/jupyter/datascience-notebook
# https://quay.io/repository/jupyter/datascience-notebook?tab=tags&tag=latest
ARG BASE_TAG=2025-05-24
FROM $BASE_IMAGE:$BASE_TAG

USER root

# Bake the notebook user's uid to the cluster NFS export's all-squash target
# (1024 = the raconteur NAS admin uid) so home/repo ownership is consistent and
# git's ownership check passes without a safe.directory workaround. gid stays
# 100 (users), which is what the export preserves. ENV NB_UID must match, or
# docker-stacks start.sh resets jovyan back to 1000 at runtime. The base env
# (/opt/conda) stays group-writable via gid 100, so installs still work without
# a chown. See home-skel/AGENTS.md.
RUN usermod -u 1024 jovyan && chown -R 1024:100 /home/jovyan
ENV NB_UID=1024

RUN apt-get update \
    && apt-get dist-upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends \
    ansible \
    ca-certificates \
    git \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Dev toolchain comes from the single source of truth (dotfiles-symm), fetched
# at build time and pinned by SHA -- no local copy to drift, no submodule.
# CI resolves dotfiles-symm main to its current SHA and passes it as a
# --build-arg (see .github/workflows/build-datascience-notebook-ssh.yaml), so
# merges to dotfiles main are adopted automatically -- no manual bump PR. The
# pinned default below is only a fallback for local/manual `buildah bud` runs
# that do not pass --build-arg; keep it roughly current. See symmatree/tiles#607.
ARG DOTFILES_REPO=https://github.com/symmatree/dotfiles-symm.git
ARG DOTFILES_REF=bded044ada2225e27a204794a0bfa9e628818461
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
# Fix linuxbrew permissions because we're running as root.
RUN git clone "${DOTFILES_REPO}" /tmp/dotfiles-symm \
    && git -C /tmp/dotfiles-symm checkout --quiet "${DOTFILES_REF}" \
    && ansible-playbook -v /tmp/dotfiles-symm/ubuntu-zsh/install-tools.ansible.yaml \
       -i localhost, --connection=local \
    && rm -rf /tmp/dotfiles-symm /var/lib/apt/lists/* \
    && chown -R 1024:100 /home/linuxbrew

COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

COPY systemctl3.py /usr/bin/systemctl
COPY sshd_config /etc/ssh/sshd_config
RUN rm -fv /etc/ssh/sshd_not_to_be_run
RUN systemctl enable ssh

# The container has no init system, so `systemctl enable ssh` never actually
# launches the daemon. The Jupyter base image runs every executable in
# before-notebook.d/ before starting the notebook server; start sshd there.
COPY start-sshd.sh /usr/local/bin/before-notebook.d/start-sshd.sh
RUN chmod a+rx /usr/local/bin/before-notebook.d/start-sshd.sh

# Home is an NFS mount that masks anything baked at /home/jovyan, so stage the
# home-dir docs at an unmasked path and copy them in via a before-notebook.d
# hook at startup. See home-skel/AGENTS.md.
COPY home-skel/AGENTS.md /opt/home-skel/AGENTS.md
COPY seed-home-docs.sh /usr/local/bin/before-notebook.d/seed-home-docs.sh
RUN chmod a+rx /usr/local/bin/before-notebook.d/seed-home-docs.sh
