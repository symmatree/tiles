# homeassistant

An [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) perimeter gate in front of the
Home Assistant appliance. This chart deploys **only the gate** -- Home Assistant itself is not a
workload in this cluster.

## Access

| URL | Purpose |
| --- | --- |
| `https://homeassistant.tiles.symmatree.com` | Home Assistant web UI, behind the gate (Google + email allowlist) |
| `https://homeassistant.local.symmatree.com:8123` | the appliance itself, LAN-only, unchanged |

The generic wiring, the WAN exposure switch and the `#593-#604` hardening rules are the shared
pattern in [docs/remote-access.md](../../docs/remote-access.md). What follows is what is different
here.

## What is different: the upstream is not in the cluster

Home Assistant runs on a HA Yellow at `10.0.99.9`, serving HTTPS on `:8123` with the
cert-manager certificate that [`charts/static-certs`](../static-certs) pushes to it daily. Every
other gated app in this cluster is a Service that gets flipped to `ClusterIP`; there is nothing to
flip here.

No `ExternalName` Service or hand-written EndpointSlice is involved. oauth2-proxy's `--upstream`
takes a URL, so the upstream is simply
`https://homeassistant.local.symmatree.com:8123`. Addressing it by the name on its certificate
means the upstream handshake verifies against the real chain -- Go takes the TLS ServerName from
the upstream URL, so `--pass-host-header=true` does not disturb it, and
`--ssl-upstream-insecure-skip-verify` is not needed.

That couples two places to the appliance's internal name: `--upstream` here, and the
`homeassistant` entry in [`charts/static-certs/values.yaml`](../static-certs/values.yaml) that
issues and pushes the certificate for it. Renaming the appliance means changing both together, or
the upstream handshake stops verifying.

## Where through-mode comes from

The requirement is that no packet reaches Home Assistant from the internet without first passing
*through* a proxy that checked identity -- not a lookaside where Home Assistant checks a token on
its own surface.

That holds, and it is worth being precise about what enforces it:

- The only WAN ingress to this site is the single UniFi `443` forward to the shared Cilium ingress
  VIP `10.0.130.1` ([`tf/nodes/port-forwards.tf`](../../tf/nodes/port-forwards.tf)). There is no
  forward for `8123` and no other forward to `10.0.99.9`.
- `homeassistant.tiles.symmatree.com` resolves (via external-dns, CNAME to `lhitw`) to that WAN address, and
  the Ingress it lands on belongs to oauth2-proxy. Home Assistant has no Ingress.
- So an internet client reaches Envoy, then oauth2-proxy, then Home Assistant -- in that order,
  with no alternative route.

**The enforcement lives in the UniFi port-forward table, not in a Kubernetes Service type.** For
Argo CD and JupyterHub the `ClusterIP` flip makes the property structural inside the cluster; here
there is no equivalent, so adding a WAN forward that reaches `10.0.99.9` would silently undo it.

`homeassistant.tiles.symmatree.com` behaves identically inside the house and outside it: it is a
single CNAME to `lhitw` for every client, so a browser on the LAN hairpins back in through the
UniFi forward and meets the same gate. One URL, one behaviour, regardless of which network a phone
has decided to attach to.

What stays on the LAN is the **machine** path. `homeassistant.local.symmatree.com` continues to
resolve straight to `10.0.99.9`, because the clients that use it cannot pass a Google challenge:
ESPHome and the device integrations, and the Alloy scrape of the unauthenticated `/api/prometheus`.
(The `static-certs` push is unaffected either way -- it SSHes to the IP, not the name.) The gate is
the human perimeter; it is not and cannot be a LAN perimeter for this host.

## Prerequisites

These are manual and are **not** created by this chart. Until they exist the gate fails closed.

1. **A Google OAuth client of its own**, `homeassistant-tiles` in the `tiles-id-7a27` project
   alongside `argocd-oauth-proxy` and `jupyterhub-tiles`, with the single redirect URI
   `https://homeassistant.tiles.symmatree.com/oauth2/callback`. Prod-only chart, so there is no
   `tiles-test` host to register.
2. **1Password item** `homeassistant-oauth2-proxy` in the `tiles-secrets` vault, with field labels
   exactly `client-id` / `client-secret` / `cookie-secret`: the first two from that client, the third
   from `openssl rand -base64 32 | tr -- '+/' '-_'`.
3. **`ha-config`**: `http.use_x_forwarded_for: true` and `http.trusted_proxies: 10.0.144.0/20`.
   oauth2-proxy sets `X-Forwarded-For` on every upstream request, and Home Assistant raises
   `HTTPBadRequest` for an `X-Forwarded-For` it was not configured to expect -- so without this the
   gate authenticates you and then every request returns 400. Landing this change early is harmless:
   nothing else sends Home Assistant an `X-Forwarded-For` today.

## The second layer is a local Home Assistant account

The shared pattern in [docs/remote-access.md](../../docs/remote-access.md) has each app reuse its
own Google client so the inner login is a near-silent redirect. That works for Argo CD (Dex) and
JupyterHub (the hub's `google` authenticator). **Home Assistant has no Google login at all**, so
there is no client to share and the inner layer is HA's own username and password.

Verified against the appliance rather than inferred from config: `/auth/providers` returns only
`{"type": "homeassistant"}`, `/auth/oidc/redirect` and `/auth/oidc/welcome` both 404, and
`/api/config` lists no OIDC component. The `auth_oidc:` block in `ha-config`'s
`configuration.yaml` is inert -- that custom component is not installed on the appliance.

The consequence is two prompts rather than one, with two different credential types. If a single
Google login is wanted later, installing hass-oidc-auth would do it, at the cost of its device-code
flow for the companion app -- which the app needs because its WebView cannot complete a Google
challenge, the same constraint that produced the mutual-TLS door below.

## Verifying the gate

Same truth table as the other gates -- read the proxy's own logs rather than trusting that a
challenge appeared:

```bash
kubectl -n homeassistant logs -l app=oauth2-proxy --since=30m \
  | grep -iE "AuthSuccess|AuthFailure|Access Denied"
```

The upstream leg is separately checkable from any pod in the pod CIDR:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://homeassistant.local.symmatree.com:8123/   # 200
```

## What this does not cover

- **The companion app.** The Android app can carry the proxy's session cookie -- `HomeAssistantApis`
  builds one `OkHttpClient` with the WebView cookie jar and hands it to Retrofit and the websocket
  alike -- but it cannot *obtain* one, because the app renders its login in an Android `WebView` and
  Google refuses OAuth in embedded webviews. The web UI installs to a phone home screen and works;
  the app still needs the LAN. A client-certificate door is the candidate follow-up.
- **The LAN.** See above.
