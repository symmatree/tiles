# JupyterHub

Wraps [zero-to-jupyterhub-k8s](https://z2jh.jupyter.org/) (`hub.jupyter.org/helm-chart ~4.2`) to provide an always-on JupyterHub with direct SSH access to the singleuser pod.

## Access

| URL | Purpose |
|-----|---------|
| `https://notebook.{cluster_name}.symmatree.com` | JupyterHub web UI, behind the oauth2-proxy perimeter (Google + email allowlist) |
| `notebook-ssh.{cluster_name}.symmatree.com:22` | Direct SSH into singleuser pod (SSH key; **separate door**, not behind the gate) |

The web UI is internet-reachable and gated by an identity-aware proxy. The access
path, the WAN exposure switch, and the perimeter hardening gotchas are the shared
pattern documented in [docs/remote-access.md](../../docs/remote-access.md); this
section covers the JupyterHub-specific parts.

## Access perimeter (oauth2-proxy)

`prod` (and `test` on-LAN) put JupyterHub behind an
[oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) subchart
(`charts/jupyterhub/Chart.yaml` dependency): Google login + an email allowlist is
the gate, `proxy-public` is flipped to `ClusterIP` so the hub is reachable **only**
through the gate, and TLS terminates at the shared Cilium ingress. The generic
wiring and the `#593-#604` hardening rules live in
[docs/remote-access.md](../../docs/remote-access.md). JupyterHub-specific notes:

- **Two Google logins, one interactive.** The perimeter (oauth2-proxy) and the
  hub (`authenticator_class: google`, `allow_all: true`) each do their own OAuth
  round-trip on different callback paths (`/oauth2/callback` vs
  `/hub/oauth_callback`), so they do not collide. Both reuse the **same** Google
  client, so the inner login is a near-silent redirect -- the user sees one
  interactive prompt. Collapsing to a single layer (hub trusting the proxy's
  `X-Auth-Request-Email` behind a NetworkPolicy) is a tracked follow-up.
- **Websockets.** Jupyter terminals and kernels are websocket-based; oauth2-proxy
  passes the upgrades by default. Verified live: a terminal + kernel run through
  the proxy.
- **SSH is not behind the gate.** `notebook-ssh...:22` is a separate LoadBalancer
  to the pod, gated by SSH key, LAN-only. The only WAN path to a shell is the
  Jupyter UI terminal, which *is* behind oauth2-proxy.
- **The gate exposes a root-capable shell** (`singleuser.uid: 0`, `GRANT_SUDO`,
  privileged) once inside, so the allowlist is the whole ballgame -- verify it
  (see the truth table in [docs/remote-access.md](../../docs/remote-access.md)).

## Image

`ghcr.io/symmatree/tiles/datascience-notebook-ssh` — built from `containers/datascience-notebook-ssh/` on push and weekly. Extends `jupyter/datascience-notebook` with openssh-server and an Ansible playbook that installs kubectl, gh, gcloud, 1password-cli, VSCode, homebrew, helm, argocd, talosctl, tanka, and go. `ARG BASE_IMAGE/BASE_TAG` allows GPU/vendor stacks (NVIDIA, ROS, Jetson) as the base. Images are public on GHCR; no pull secret is needed.

The build tags each image with an immutable `sha-<short>` tag (docker/metadata `type=sha`) alongside `edge`. `values.yaml` pins the `sha-<short>` tag with `pullPolicy: IfNotPresent` — the ~4GB image is pulled once when the tag changes, not on every pod spawn (which `edge` + `Always` did). Roll forward by bumping `singleuser.image.tag` to the newer `sha-<short>` from the build run.

The singleuser pod runs as root (`uid: 0`) with `SYS_ADMIN` + `DAC_READ_SEARCH` capabilities to support bind mounts and FUSE filesystems. Culling is disabled — the pod is intended to stay alive as a persistent SSH target. In prod it is pinned to `lancer` (128GB metal) via `values-tiles.yaml` `nodeSelector`, because the image unpacks at node level (not bounded by a pod limit) and needs a node that can absorb the transient (see #576).

## SSH selector stability

The SSH LoadBalancer selects pods on `tiles.symmatree.com/user: seth`, set via `c.KubeSpawner.extra_labels` in hub config. This is stable across pod restarts. The upstream chart also stamps pods with `hub.jupyter.org/username: {hash}` but that hash is hard to predict and changes with username format changes; the custom label avoids that dependency.

## SSH access

End-to-end SSH is **working**: `ssh jovyan@notebook-ssh.{cluster_name}.symmatree.com` (port 22, the default; key from the `jupyterhub-ssh-key` 1Password item). `PermitRootLogin` is `no`, so log in as `jovyan` (the image drops to `NB_USER` after root-time setup).

How the pieces fit — each of these was a distinct fix (PRs #538, #546, #553, #570):

1. **Start `sshd`** — the container has no init system, so `systemctl enable ssh` never launches the daemon. `before-notebook.d/start-sshd.sh` (run by the base image's `start.sh`) launches it on every start.
2. **`/run/sshd`** — `sshd` exits 255 without its privilege-separation dir; `/run` is an empty tmpfs, so the hook `mkdir -p /run/sshd`.
3. **Don't break `start.sh`** — the hook is *sourced*, so its `set -euo pipefail` is wrapped in a subshell; a bare `set -u` leaked into `start.sh` (which references an unset `JUPYTER_DOCKER_STACKS_QUIET`) and aborted startup. A broken `sshd` now logs and lets the notebook come up without SSH rather than crashlooping.
4. **Find the key** — the mounted key lives at `/mnt/keys/authorized_keys`, but sshd's default `AuthorizedKeysFile` is `~/.ssh/authorized_keys` and nothing populates it; pointing sshd straight at `/mnt/keys` fails `StrictModes` (the secret mount dir is world-writable). The hook copies the key to root-owned `/etc/ssh/authorized_keys` and `sshd_config` sets `AuthorizedKeysFile` there.

The `ssh-service` LoadBalancer (`external-dns` → `notebook-ssh.{cluster}.symmatree.com`) selects the pod on the stable `tiles.symmatree.com/user` label (see below).

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
| oauth2-proxy gate (`client-id`/`client-secret`/`cookie-secret`) | Manual | `jupyterhub-oauth2-proxy` | Perimeter gate. `client-id`/`client-secret` **reuse** the `jupyterhub-oauth-client` values (add the `/oauth2/callback` redirect URI to that same GCP client); `cookie-secret` is a fresh URL-safe 32-byte value. See [docs/remote-access.md](../../docs/remote-access.md). |
| SSH authorized key | Manual | `jupyterhub-ssh-key` | Shared (no cluster prefix): same keypair works across clusters. |

### OAuth scopes

`GoogleOAuthenticator` requests `openid` and `email` by default — no `profile`. Both are non-sensitive scopes; the consent screen does not need to go through Google's verification process and they work in Testing publishing status.

If `allowed_google_groups` or `admin_google_groups` were configured, the authenticator would also request `https://www.googleapis.com/auth/admin.directory.group.readonly`, which requires Google Workspace admin access and domain-wide delegation on a service account. That is not configured here — `allow_all: true` with an explicit admin user list is used instead.

### Google OAuth — one app, two redirect URIs

Both `tiles` and `tiles-test` share the `tiles-secrets` 1Password vault and therefore share one `jupyterhub-oauth-client` item. A single GCP OAuth 2.0 client (Web Application) is registered with both redirect URIs:

- `https://notebook.tiles.symmatree.com/hub/oauth_callback`
- `https://notebook.tiles-test.symmatree.com/hub/oauth_callback`

The `oauth_callback_url` in each cluster's JupyterHub config is set to its own URL via `application.yaml` `valuesObject`; Google validates the redirect against its allowlist. The client_id and client_secret are the same for both clusters.

Create in the **`tiles-id`** GCP project (the shared identity project). The choice of project doesn't affect which GCP services JupyterHub can call — SA grants for that live in `tiles-main`/`tiles-test-main`. It's tiles-id because the OAuth consent screen is identity infrastructure shared across environments, same as the workload identity pool.

This is permanently manual: GCP has no API for creating OAuth clients for external apps (the Terraform `google_iap_brand`/`google_iap_client` route was internal-org-only and shut down March 2026). The `tiles-terraform-oidc` SA only has `roles/viewer` on `tiles-id` anyway.

### Terraform resources

`tf/modules/k8s-cluster/k8s-jupyterhub.tf` — follows the same `random_password` + `onepassword_item` pattern as `apprise.tf`. Applied automatically by the `nodes-plan-apply` CI workflow on merge.

## Per-cluster overrides

| File | Purpose |
|------|---------|
| `values-tiles.yaml` | Production overrides: pin singleuser to `lancer` (128GB metal) |
| `values-tiles-test.yaml` | Reduced resources: hub 128Mi, proxy 64Mi, singleuser 1G/512M guarantee, userScheduler disabled |

## Persistence model

Three tiers:

1. **Image baseline** — tools installed at build time (Ansible playbook)
2. **Ephemeral container FS** — writable overlay, lost on pod restart
3. **Home directory** — survives restarts; Claude Code session history at `~/.claude/projects/…` lives here.

Home is a **static NFS volume** (`templates/home-nfs.yaml`), not a dynamic PVC. One shared RWX PV on the NAS (`raconteur:/volume2/{cluster}/jupyterhub-home`, `Retain`) is mounted with a per-user `subPath: {username}` (z2jh `storage.type: static`), so each user gets a stable, named directory `…/jupyterhub-home/<username>` that persists independently of the pod/PVC lifecycle. This replaced the default dynamic `local-path` PVC, which was node-local and pinned the pod to one worker's disk — starving that node and blocking the `lancer` nodeSelector. NFS has no node affinity, so the pod is free to schedule on `lancer`. The `jupyterhub-home` directory must exist under the cluster NFS share (manual NAS step, alongside `loki-data`/`mimir-data`).
