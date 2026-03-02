# JupyterHub Integration

## Purpose

Port the JupyterHub deployment from [tales/jupyterhub](https://github.com/symmatree/tales/tree/main/jupyterhub)
into tiles, providing a persistent Jupyter/shell environment with SSH access
for remote development via VSCode and Cursor.

## What It Provides

- **Jupyter notebook server** in Kubernetes with persistent home directory storage
- **Google OAuth login** for identity (single-user for now)
- **SSH access** to the notebook pod, enabling Cursor's `Remote-SSH` and
  general-purpose terminal access
- **VSCode Tunnel** capability from the Jupyter terminal (for `Remote-Tunnel` access)
- **Privileged container** with sudo, enabling `systemctl start ssh`, tool
  installation, and container builds via buildah
- **Custom image** based on `jupyter/datascience-notebook` with pre-installed
  tools (kubectl, helm, gh, 1password-cli, go, etc.)

## Design Decisions

### Helm chart wrapping upstream JupyterHub

Follows the existing tiles pattern: a local chart in `charts/jupyterhub/` that
declares the upstream `jupyterhub` chart (from `https://hub.jupyter.org/helm-chart`)
as a dependency, with local templates for supporting resources (1Password secrets,
TLS certificates, SSH service).

### DNS uses cluster-scoped hostnames

Tales used `notebook.local.symmatree.com` (hardcoded). Tiles uses the
`{cluster_name}.symmatree.com` pattern, so this becomes:

- `notebook.{cluster_name}.symmatree.com` — JupyterHub web UI
- `notebook-ssh.{cluster_name}.symmatree.com` — SSH service

This means the test cluster gets its own independent JupyterHub instance with
a different hostname, which is the desired behavior (test the deployment
without breaking production).

### 1Password vault parameterized via `vault_name`

Tales hardcoded `tales-secrets` as the vault. Tiles passes `vault_name`
through ArgoCD values, so the same chart works with different vaults per
cluster. The 1Password items need to exist in whatever vault is configured:

- `jupyterhub-oauth-client` — Google OAuth client ID and secret
- `jupyterhub-ssh-key` — SSH public key for authorized_keys
- `jupyterhub-github-token` — GHCR pull token (dockerconfigjson format)

### Modest resource requests

The issue notes tiles-test is near capacity. The chart does not set explicit
CPU/memory requests on the hub or singleuser pods beyond the upstream defaults.
The singleuser storage request is kept at 100Gi (needed for buildah and
general development work). If this is too large for test, it can be overridden
per-cluster in the ArgoCD application values.

### Node affinity left unspecified

The issue mentions pinning to "lancer" or "rising" in the future but leaving
it unspecified for now. The values.yaml does not include nodeSelector or
affinity for singleuser pods. When ready, this can be added as:

```yaml
jupyterhub:
  singleuser:
    nodeSelector:
      kubernetes.io/hostname: lancer  # or rising
```

### Namespace security: privileged

The ArgoCD application sets `pod-security.kubernetes.io/enforce: privileged`
on the namespace, matching tales. This is required for SSH, sudo, and
buildah inside the notebook containers.

## Rejected Alternatives

### Tanka instead of Helm chart

Some tiles applications (apprise, monitoring mixins) use Tanka/Jsonnet.
However, JupyterHub's upstream provides a well-maintained Helm chart, and
the existing tales deployment used Helm values directly. Wrapping it as a
Helm chart dependency is simpler and more maintainable than translating
the extensive values.yaml into Jsonnet.

### Ingress instead of LoadBalancer for HTTPS

Grafana and other tiles services use Cilium ingress with cert-manager
annotations. JupyterHub's proxy architecture (configurable-http-proxy)
works best with a LoadBalancer service and direct TLS termination. The
upstream chart has first-class support for this via `proxy.https`. Using
ingress would require disabling the built-in proxy TLS and configuring
WebSocket passthrough, which adds complexity without benefit. The SSH
service also requires a separate LoadBalancer regardless.

### Multiple auth providers

GitHub auth would avoid the need for a Google OAuth application. However,
the tales setup already used Google auth, the user is the Google account
owner, and there's an existing 1Password item for it. Switching to GitHub
auth could be a future change but isn't worth the friction now.

### Running the notebook pod as non-root

The upstream images support this, but SSH, sudo, systemctl, and buildah
all require root (or extensive capability configuration). The tales setup
ran as uid 0 with GRANT_SUDO and privileged containers. This is acceptable
for a single-user development environment.

## Prerequisites / Manual Steps

### Google OAuth Application

Google OAuth credentials cannot currently be created through Terraform.
A Google Cloud OAuth 2.0 Client ID must be created manually:

1. Go to [Google Cloud Console > APIs & Services > Credentials](https://console.cloud.google.com/apis/credentials)
2. Create an OAuth 2.0 Client ID (Web application type)
3. Add authorized redirect URI: `https://notebook.{cluster_name}.symmatree.com/hub/oauth_callback`
4. Store the client ID and secret in 1Password as `jupyterhub-oauth-client`
   with fields `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET`

If deploying to both test and production clusters with different hostnames,
either create two OAuth clients (one per redirect URI) or add both redirect
URIs to the same client and share the same 1Password item.

### 1Password Items

These items must exist in the vault referenced by `vault_name`:

| Item Name | Type | Fields / Notes |
|-----------|------|----------------|
| `jupyterhub-oauth-client` | Opaque | `OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET` |
| `jupyterhub-ssh-key` | Opaque | `public-key` (SSH authorized_keys content) |
| `jupyterhub-github-token` | dockerconfigjson | GHCR pull credentials (use `make-pull-token.sh`) |

### Custom Docker Image

The custom `datascience-notebook-ssh` image must be built and pushed to
`ghcr.io/symmatree/internal/datascience-notebook-ssh`. The `docker/`
directory contains the Dockerfile and build script. This is currently a
manual build process run from within the notebook environment itself
(or any machine with buildah and GHCR credentials).

## Open Questions

1. **Shared OAuth client across clusters?** A single Google OAuth client
   can have multiple redirect URIs. Should we use one client for both
   tiles and tiles-test, or separate ones? Using one is simpler but means
   the test cluster can authenticate against production's OAuth client.

2. **Image build automation.** The tales setup built images manually from
   inside the notebook pod. Should we add a GitHub Actions workflow to
   build the image on push to `docker/`? This would standardize the build
   but adds CI complexity. The image changes infrequently.

3. **Storage class for tiles-test.** The 100Gi PVC may not be available
   in tiles-test depending on storage provisioner capacity. Should we
   lower it for test (e.g. 10Gi) or just accept that test may not have
   enough storage?

4. **SSH service username hash.** The SSH service selector uses
   `hub.jupyter.org/username: seth-porter-gmail-com---39d0c2f0`. The
   suffix appears to be a truncated hash of the username. JupyterHub
   generates this via its `safe_slug` function. We could pre-compute
   this, but it's fragile. For now the SSH service selector is
   parameterized via `sshUser` in values.yaml and defaults to the known
   value. If a way to predict or configure this slug is found, it can
   be updated.

5. **Cull timeout.** Tales disabled culling entirely (`cull.enabled: false`)
   because the point is to keep the dev environment alive. This is
   appropriate for production but might waste resources on test. Should
   test enable culling with a timeout?

6. **VPN/network access.** The notebook is exposed on the local network
   via external-dns. Access from outside the network requires VPN. This
   is unchanged from tales and not addressed here.
