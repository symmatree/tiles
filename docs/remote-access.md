# Remote Access -- the identity-aware perimeter

How services in the cluster are reached from outside the LAN, and the security
model that gates them. The goal is BeyondCorp-style: **no packet reaches an
application without first being tied to a validated, allowlisted identity**, and
the thing doing the gating is a small, single-purpose proxy rather than the large
attack surface of the app behind it (Grafana, JupyterHub, Argo CD).

There is no VPN. Every protected host is published to the public internet and
fronted by [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/), which
challenges for Google identity and admits only an explicit email allowlist. A
request that is unauthenticated, or authenticated as the wrong identity, never
reaches the upstream.

## The pattern

Each protected app gets its own `oauth2-proxy` (a subchart dependency of the
app's chart) sitting in front of it on the shared Cilium ingress:

- oauth2-proxy is the **only** thing with an Ingress; the app's own Service is
  flipped to `ClusterIP` so it is reachable *only* through the gate.
- Google OAuth + an **email allowlist** (`--authenticated-emails-file`) is the
  real gate. There is no domain rule -- the allowlist is the sole restriction.
- TLS terminates once, at the shared Cilium ingress (cert-manager `real-cert`).

Currently protected this way:

| App | Host | Gate config | Chart |
|-----|------|-------------|-------|
| Argo CD | `argocd.{cluster}.symmatree.com` | `charts/argocd/values.yaml` (`oauth2-proxy:` block) | `charts/argocd` |
| JupyterHub | `notebook.{cluster}.symmatree.com` | `charts/jupyterhub/values.yaml` (`oauth2-proxy:` block) | `charts/jupyterhub` ([README](../charts/jupyterhub/README.md)) |

Each has its own oauth2-proxy Deployment and its own 1Password item (see
[Secrets](#secrets)). The two configs are intentionally near-identical -- the
hardening lessons below were paid for once on Argo CD and copied to JupyterHub.

## The access path, end to end

```
Internet client
  -> DNS: notebook.tiles.symmatree.com
          external-dns publishes a CNAME -> lhitw.symmatree.com
          (lhitw = the UniFi/Cloudflare dynamic-DNS record tracking the WAN IP)
  -> WAN IP :443
          UniFi port-forward (tf/nodes/port-forwards.tf), PROD ONLY
  -> 10.0.130.1
          the shared Cilium ingress VIP (ingress_lb_ip, pinned in the
          10.0.130.0/24 LB pool; see charts/cilium-config)
  -> Cilium ingress (Envoy)
          TLS terminates here (cert-manager real-cert); Envoy SNATs the client
          into the pod CIDR 10.0.144.0/20
  -> oauth2-proxy (Deployment <app>-oauth2-proxy)
          Google auth + email allowlist -- the gate
  -> upstream app Service (ClusterIP: proxy-public / argocd-server)
```

On the **LAN**, split-horizon DNS resolves the host to the internal ingress VIP
directly, so it is reachable on-network even without the WAN plumbing. That is
why an on-LAN test is only a partial test -- it exercises the gate but not the
WAN port-forward / DNS path.

### The WAN exposure switch

Exposure is one annotation on the oauth2-proxy Ingress:

```yaml
external-dns.alpha.kubernetes.io/target: lhitw.symmatree.com
```

- **With** it: external-dns publishes the host as a CNAME to `lhitw` (the WAN
  record), so external clients resolve it and reach the UniFi 443 forward.
- **Without** it: external-dns publishes the host at the internal ingress VIP --
  reachable on-LAN only. This is the safe, testable-first state.

external-dns runs `policy: sync` (not `upsert-only`) specifically so the A ->
CNAME record-type flip on the WAN cutover succeeds (upsert-only cannot change a
record's type). It only touches records it owns (txt registry, `txtOwnerId =
cluster`), so it will not clobber the hand-managed `lhitw` record.

The **test cluster has no front door**: `tf/nodes/prod.tfvars` sets
`ingress_lb_ip = "10.0.130.1"`, but test leaves `ingress_lb_ip` empty, so neither
the pinned ingress VIP nor the UniFi 443 port-forward exists there. `tiles-test`
hosts are LAN-only regardless of the annotation.

## Configuration gotchas

These are the traps that make an auth perimeter *look* like it works while
silently letting the wrong people in (or 404ing legitimate ones). Every one cost
a debugging session on Argo CD (refs #593-#604); they are baked into both
`values.yaml` files with inline comments.

| Gotcha | Rule | Why (failure mode) |
|--------|------|--------------------|
| Placeholder secret collision (#600) | Set `config.existingSecret` to the 1Password-backed Secret | Without it the chart renders its *own* Secret full of `XXXXXXX`; Argo self-heal races it and sends `client_id=XXXXXXX` to Google -- the authorize step is rejected and no callback returns. |
| Ingress path match (#601) | `ingress.pathType: Prefix` | Cilium + the chart-default `ImplementationSpecific` matches only the exact `/`, so `/oauth2/callback` and the whole app 404 at Envoy before reaching the proxy. |
| `--email-domain` (#602) | Do **not** set it | Email validation is OR, not AND: `--email-domain=*` is allowAll, so every Google account passes and the allowlist is never consulted. |
| `email_domains` in configFile (#603) | Override the chart default to drop the `[ "*" ]` | Same allowAll wildcard, hiding in the config file instead of a flag. Dropping only the flag is not enough. |
| Trusted proxies (#604) | `--trusted-proxy-ip=10.0.144.0/20` (pod CIDR) | With `--reverse-proxy` and no restriction, `X-Forwarded-*` is trusted from `0.0.0.0/0`. The Cilium ingress Envoy SNATs into the pod CIDR, so trusting *that* covers every legitimate ingress source and excludes external clients. Node IPs are heterogeneous, so the pod CIDR -- not node subnets -- is the boundary. |
| Cookie secret encoding | `openssl rand -base64 32 \| tr -- '+/' '-_'` (URL-safe) | oauth2-proxy decodes the cookie secret with `base64.RawURLEncoding`; standard-base64 `+`/`/` fails to decode and it falls back to the raw 44-byte string -> not a valid AES key length -> the pod fails to start. |
| Image pin | Pin a current patched tag (e.g. `v7.15.3`), not the chart default | This is the internet-facing auth gate; track upstream security fixes rather than riding an older chart-default image. |

## App-of-apps propagation gotcha

This cluster is app-of-apps: a parent Argo Application (`argocd-applications`)
writes each child Application's `valuesObject`, including the per-cluster host.
After a tag move, the child app can sync the **new chart** before the parent has
written the **new valuesObject** -- so for a wave the oauth2-proxy Ingress renders
with the chart-default `notebook.placeholder.symmatree.com` host (and its cert
cannot issue). This is normal mid-propagation, not a bug: once the parent syncs,
the child re-renders with the real host and the cert issues. If it stays on
`placeholder`, the parent app is stuck -- check `argocd-applications` health, not
the child. See [config-propagation.md](config-propagation.md) and
[environment-strategy.md](environment-strategy.md) (reconcile timing / tag-based
deploys).

## Secrets

Each app has a 1Password item (in the per-cluster `tiles-secrets` vault) that
backs the oauth2-proxy `existingSecret`, with keys **exactly**
`client-id` / `client-secret` / `cookie-secret`:

- `client-id` / `client-secret`: **reuse the app's existing Google OAuth client**
  (the same one the app uses for its own login), and add the redirect URI
  `https://{host}/oauth2/callback` to it. Reusing the client avoids a second
  consent screen and a second app identity to verify/revoke.
- `cookie-secret`: a fresh 32-byte URL-safe value (see the encoding gotcha above).
  It is oauth2-proxy's session-cookie key only -- unrelated to Google;
  regenerating it just logs everyone out.

See [secrets.md](secrets.md) for the vault layout, and the per-app README for the
exact item name (e.g. `jupyterhub-oauth2-proxy`).

## Verifying the gate

The security boundary is provable from the oauth2-proxy logs -- read them rather
than trusting that a challenge appeared:

```bash
kubectl -n <namespace> logs -l app=oauth2-proxy --since=30m \
  | grep -iE "AuthSuccess|AuthFailure|Access Denied"
```

The full truth table (verified live for JupyterHub, 2026-07-24):

| Who | Expected | Log signal |
|-----|----------|------------|
| Allowlisted email | admitted, proxied upstream | `[AuthSuccess] Authenticated via OAuth2: ...email:<you>` then `200` to the app |
| Valid Google account, **not** allowlisted | **403** | `[AuthFailure] Invalid authentication via OAuth2: unauthorized` + `403` on `/oauth2/callback` |
| No auth (e.g. an internet scanner) | denied | `No valid authentication in request. Access Denied.` (`302`/`403`) |

The third row shows up unprompted in the logs -- the host is on the public
internet, so background scanners hit it constantly and bounce off. That is the
gate failing closed against real traffic.

## What the gate does NOT cover

- **JupyterHub SSH is a separate door.** `notebook-ssh.{cluster}.symmatree.com:22`
  is a `type: LoadBalancer` straight to the singleuser pod, gated by SSH public
  key (`authorized_keys`), entirely outside oauth2-proxy. It is LAN-only (no
  external-dns WAN target) and is intended to stay that way; the only WAN path to
  a shell is indirectly through the Jupyter UI terminal, which *is* behind the
  gate. See [charts/jupyterhub/README.md](../charts/jupyterhub/README.md).
- **Double login (JupyterHub).** The perimeter and the hub each still do their
  own Google round-trip; sharing the client makes the inner one a near-silent
  redirect. Collapsing it to one login (hub trusting the proxy's
  `X-Auth-Request-Email` header behind a NetworkPolicy) is a tracked follow-up.

## See also

- [charts/jupyterhub/README.md](../charts/jupyterhub/README.md) -- JupyterHub's
  specific integration (double-Google flow, websockets, the separate SSH door).
- `charts/argocd/values.yaml` -- the reference oauth2-proxy config with inline
  rationale for every flag.
- [cluster-network.md](cluster-network.md) -- ingress, LB pools, pod CIDR.
- [secrets.md](secrets.md) -- 1Password vault layout.
- [config-propagation.md](config-propagation.md) / [environment-strategy.md](environment-strategy.md)
  -- app-of-apps values flow and tag-based deploy timing.
