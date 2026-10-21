# fleet-control-gate

An [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) perimeter gate in front of
[fleet-control](../../tanka/environments/fleet-control), for reaching it from off the LAN. This
chart deploys only the gate, into the `fleet-control` namespace beside the service it fronts.

## Access

| URL | Purpose |
| --- | --- |
| `https://fleet-remote.tiles.symmatree.com` | fleet-control web UI and API, behind the gate (Google + email allowlist) |
| `https://fleet.tiles.symmatree.com` | fleet-control's own Ingress, LAN-only, unchanged |

The generic wiring, the WAN exposure switch and the `#593-#604` hardening rules are the shared
pattern in [docs/remote-access.md](../../docs/remote-access.md).

## What is different: the app keeps its own LAN door

Elsewhere the gated app's Service is the only way in and the gate holds its one Ingress. Here
fleet-control keeps its own LAN Ingress on `fleet.{cluster}.symmatree.com`, because the fleet
devices use that address: `FLEET_PUBLIC_URL` is where a device downloads from during a converge,
and devices cannot complete a Google login. The bench harness and the API examples in the
coordinator repo use it too. That Ingress has no `external-dns` WAN target, so it is published at
its LAN address only; the gate is the internet perimeter, not a LAN perimeter.

fleet-control has no login of its own, so the gate is the only layer on the WAN path.

## Secrets

1Password item `fleet-control-oauth2-proxy` in the cluster vault, fields `client-id`,
`client-secret` and `cookie-secret` (see [docs/remote-access.md#secrets](../../docs/remote-access.md#secrets)).
The Google client needs the redirect URI `https://fleet-remote.tiles.symmatree.com/oauth2/callback`.
