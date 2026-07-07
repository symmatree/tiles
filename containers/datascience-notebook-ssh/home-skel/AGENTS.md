# Working in this JupyterHub home

Orientation for anyone -- human or coding agent -- working in this notebook
environment on the tiles cluster.

## What this is

A JupyterHub single-user server (image `datascience-notebook-ssh`, based on
jupyter/docker-stacks). Your home directory is a static NFS volume served from
the `raconteur` NAS. That NFS export squashes every client write to a single uid
(1024, the NAS `admin` account), so files here show owner `1024` -- and the
notebook process is built to run as uid `1024` to match, which is why git and
other ownership-sensitive tools work without a `safe.directory` workaround.

Only your home (and the shared `datasets/` mount) persist. The rest of the
container filesystem is disposable and resets when the pod restarts.

## Source of truth (edit these, not the running container)

- Image build (Dockerfile):
  https://github.com/symmatree/tiles/blob/main/containers/datascience-notebook-ssh/Dockerfile
- Baked dependencies (Ansible playbook):
  https://github.com/symmatree/tiles/blob/main/containers/datascience-notebook-ssh/install-tools.ansible.yaml
- JupyterHub deployment (image tag, singleuser config, NB_UID):
  https://github.com/symmatree/tiles/blob/main/charts/jupyterhub/values.yaml
- NFS home volume:
  https://github.com/symmatree/tiles/blob/main/charts/jupyterhub/templates/home-nfs.yaml

## Changing dependencies

The pattern is: test at runtime, then bake it in so it survives a restart.

1. Test in the running container. `pip install <pkg>` writes into the base env
   (group-writable via gid 100, so no sudo needed); `sudo pip install` and
   `sudo apt-get install` also work (sudo is granted). Iterate until it works.
   These runtime installs are disposable -- they vanish on pod restart.
2. Bake it into the image so it sticks: add the dependency to the Ansible
   playbook (link above) -- Python packages to the pip task, system packages to
   the apt task -- and open a PR to the `tiles` repo.
3. Ship it: merging triggers the image build workflow, which pushes a new
   `sha-<short>` tag. Bump `singleuser.image.tag` in the JupyterHub
   `values.yaml` to that tag; ArgoCD deploys it.

This is the same discipline as committing a working experiment out of a
disposable scratch layer into the base -- iterate in the throwaway space, then
promote the result into source.

## Note

This file is generated from the image (staged at `/opt/home-skel/AGENTS.md` and
copied in on each pod start), so local edits here are overwritten on restart.
Edit the source in the repo:
https://github.com/symmatree/tiles/blob/main/containers/datascience-notebook-ssh/home-skel/AGENTS.md
