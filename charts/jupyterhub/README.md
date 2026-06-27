# JupyterHub

Wraps [zero-to-jupyterhub-k8s](https://z2jh.jupyter.org/) (`hub.jupyter.org/helm-chart ~4.2`) to provide an always-on JupyterHub with direct SSH access to the singleuser pod.

## Access

| URL | Purpose |
|-----|---------|
| `https://notebook.{cluster_name}.symmatree.com` | JupyterHub web UI (Google OAuth) |
| `notebook-ssh.{cluster_name}.symmatree.com:22` | Direct SSH into singleuser pod |

## Image

`ghcr.io/symmatree/tiles/datascience-notebook-ssh` — built weekly from `containers/datascience-notebook-ssh/`. Extends `jupyter/datascience-notebook` with openssh-server and an Ansible playbook that installs kubectl, gh, gcloud, 1password-cli, VSCode, homebrew, helm, argocd, talosctl, tanka, and go. `ARG BASE_IMAGE/BASE_TAG` allows GPU/vendor stacks (NVIDIA, ROS, Jetson) as the base. Images are public on GHCR; no pull secret is needed.

The singleuser pod runs as root (`uid: 0`) with `SYS_ADMIN` + `DAC_READ_SEARCH` capabilities to support bind mounts and FUSE filesystems. Culling is disabled — the pod is intended to stay alive as a persistent SSH target.

## SSH selector stability

The SSH LoadBalancer selects pods on `tiles.symmatree.com/user: seth`, set via `c.KubeSpawner.extra_labels` in hub config. This is stable across pod restarts. The upstream chart also stamps pods with `hub.jupyter.org/username: {hash}` but that hash is hard to predict and changes with username format changes; the custom label avoids that dependency.

## Secrets architecture

### hub.existingSecret

`hub.existingSecret: hub-credentials` mounts the `hub-credentials` k8s Secret at `/usr/local/etc/jupyterhub/existing-secret/`. The hub's `get_secret_value()` function checks this mount before the chart-managed Secret, so Terraform-generated values take precedence at runtime for `cookie_secret` and `CryptKeeper.keys`.

### What comes from where

| Secret | Source | 1Password item | Notes |
|--------|--------|----------------|-------|
| `cookie_secret` | Terraform `random_password` | `{cluster_name}-jupyterhub-hub-credentials` | Per-cluster; via `hub.existingSecret` at runtime |
| `CryptKeeper.keys` | Terraform `random_password` | `{cluster_name}-jupyterhub-hub-credentials` | Per-cluster; via `hub.existingSecret` at runtime |
| `proxy.secretToken` (auth_token) | Chart placeholder in `values.yaml` | — | Cannot be externalized: the chart hardwires `CONFIGPROXY_AUTH_TOKEN` from the chart-managed Secret, bypassing `existingSecret`. Stable across upgrades via Helm `lookup()`. |
| Google OAuth `client_id`/`client_secret` | Manual | `jupyterhub-oauth-client` | Shared (no cluster prefix): both clusters use the same GCP OAuth app with both redirect URIs registered. See below. |
| SSH authorized key | Manual | `jupyterhub-ssh-key` | Shared (no cluster prefix): same keypair works across clusters. |

### Google OAuth — one app, two redirect URIs

Both `tiles` and `tiles-test` share the `tiles-secrets` 1Password vault and therefore share one `jupyterhub-oauth-client` item. A single GCP OAuth 2.0 client (Web Application) is registered with both redirect URIs:

- `https://notebook.tiles.symmatree.com/hub/oauth_callback`
- `https://notebook.tiles-test.symmatree.com/hub/oauth_callback`

The `oauth_callback_url` in each cluster's JupyterHub config is set to its own URL via `application.yaml` `valuesObject`; Google validates the redirect against its allowlist. The client_id and client_secret are the same for both clusters.

This will be automated alongside ArgoCD Dex Google login in a follow-on PR.

### Terraform resources

`tf/modules/k8s-cluster/k8s-jupyterhub.tf` — follows the same `random_password` + `onepassword_item` pattern as `apprise.tf`. Applied automatically by the `nodes-plan-apply` CI workflow on merge.

## Per-cluster overrides

| File | Purpose |
|------|---------|
| `values-tiles.yaml` | Production overrides (currently empty stub) |
| `values-tiles-test.yaml` | Reduced resources: hub 128Mi, proxy 64Mi, singleuser 1G/512M guarantee, PVC 10Gi, userScheduler disabled |

## Persistence model

Three tiers:

1. **Image baseline** — tools installed at build time (Ansible playbook)
2. **Ephemeral container FS** — writable overlay, lost on pod restart
3. **PVC home directory** (100Gi prod, 10Gi test) — survives restarts; Claude Code session history at `~/.claude/projects/…` is persistent here
