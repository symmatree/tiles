# NTRIP / RTKBase (prod)

GNSS base + local NTRIP caster. The receiver is an attic ZED-F9P reached over the network via
[`firmware/gnss-bridge/`](../../../firmware/gnss-bridge/README.md), so this pod has no device,
no storage and no node of its own. Prod only (`cluster_name: tiles`); there is no bridge on
test.

## Endpoints

| Service | URL | Auth |
|---------|-----|------|
| NTRIP caster | `ntrip.tiles.symmatree.com:2101` / mountpoint `ATTIC` | `gps` / `gps` (also in 1Password `{cluster}-ntrip-caster-auth`) |
| Admin web UI | `https://ntrip-admin.tiles.symmatree.com` | RTKBase default `admin` / `admin` |

Both hostnames resolve to **private 10.x addresses** on the site LAN (Cilium LoadBalancer pool `10.0.129.0/24` on prod). external-dns provides convenient names; there is no public internet exposure.

## Architecture

- **Image:** [`containers/rtkbase/`](../../../containers/rtkbase/)
- **Terraform:** [`tf/modules/k8s-cluster/ntrip.tf`](../../../tf/modules/k8s-cluster/ntrip.tf) (caster creds reference in 1Password)
- **Tanka:** [`main.jsonnet`](main.jsonnet)
- **Argo CD:** [`application.helm.yaml`](application.helm.yaml) (prod only: `cluster_name == tiles`)

Pod runs **privileged** -- only because the image runs systemd as PID 1 -- with an emptyDir at
`/persist/rtkbase` holding `settings.conf`, bind-mounted into `/root/rtkbase/settings.conf` on
boot. No hostPath device, no PersistentVolume, no nodeSelector and no toleration: the receiver
is a TCP endpoint, so the pod schedules on any worker. `strategy: Recreate`, because two pods
would both dial the bridge and it fans one UART through a single shared ring buffer.

NTRIP is exposed via LoadBalancer + external-dns; the web UI via Ingress + cert-manager (TLS
only).

`[main] ext_tcp_source` / `ext_tcp_port` in [`settings.conf`](settings.conf) is the bridge's
address, and is the whole cutover: change it and Argo rolls the pod.

## Configuration: git is authoritative

[`settings.conf`](settings.conf) in this directory is the **single source of truth** for
`/root/rtkbase/settings.conf` on the device. The loop:

1. `main.jsonnet` stamps `std.md5(importstr 'settings.conf')` into the pod template as the
   `rtkbase-settings-hash` annotation.
2. Editing the file therefore changes the pod template, so Argo CD rolls the Deployment
   (`strategy: Recreate`, so a full stop/start -- see the interruption note below).
3. The `seed-settings` init container **unconditionally overwrites** the emptyDir copy from
   the ConfigMap on every start.

So: **edit here, merge, and the change lands on the next sync.** No manual step.

### The web UI is for inspection, not configuration

Anything changed through the RTKBase web UI writes to the emptyDir copy and **survives only
until the next pod restart** -- including restarts you did not ask for (node reboot, image update,
eviction). It will then silently revert to whatever is in git, with no warning in the UI.

If you want a setting to stick, put it in [`settings.conf`](settings.conf).

The one exception is `flask_secret_key`, which RTKBase generates on boot and writes back. It
is not in git and does not need to be; regenerating it only invalidates existing web sessions.

### No raw observation log

This base does not write one -- RTK is the product. See
[`containers/rtkbase/README.md`](../../../containers/rtkbase/README.md) for why that costs
nothing and how an on-demand capture for a PPP solve works. Existing observations stay under
`datasets/gps-logs/attic-rtk-base/` with nothing writing to them; `fleet-control` still mounts
that share read-only.

### Restarting interrupts corrections

A config change restarts the pod, which drops the caster and the connection to the bridge.
The bridge discards receiver bytes while nothing is connected, so a rover loses its
corrections for the duration and reacquires -- seconds, not a lost dataset. There is no
in-progress capture to cut short any more.

### History

This used to be a first-boot **seed**: the init container copied only `if [ ! -f ... ]`. Since
the hash annotation still rolled the pod on any edit, the result was a restart that applied
nothing, and every real change had to go through the web UI -- the on-box-override drift trap
[`docs/deployment-model.md`](../../../docs/deployment-model.md) exists to prevent (same class
as #48). Changed in the PR for coordinator#199.

## Authentication

**Web UI:** RTKBase ships with username `admin` and password `admin` ([upstream default](https://github.com/Stefal/rtkbase/)). Ingress adds HTTPS; no extra auth layer.

**NTRIP caster:** `gps` / `gps` (in [`settings.conf`](settings.conf); also in 1Password `{cluster}-ntrip-caster-auth`). Matches historical field clients (SW Maps, u-center, etc.).

## Receiver-side configuration

The receiver's own config -- `CFG-TMODE`, which messages are enabled on which port, the UART
baud rate -- lives in its flash, not here, and is the one part of this base that is not in git
([#704](https://github.com/symmatree/tiles/issues/704)).
[`firmware/gnss-bridge/receiver-config.py`](../../../firmware/gnss-bridge/receiver-config.py)
reads and writes it, over USB or through the `:5015` relay.

## Dependencies

- [cert-manager](../../../charts/cert-manager/README.md), [external-dns](../../../charts/external-dns/README.md), [OnePassword operator](../../../charts/onepassword/README.md), [Cilium LB pool](../../../charts/cilium-config/)
- [`firmware/gnss-bridge/`](../../../firmware/gnss-bridge/README.md) reachable at
  `[main] ext_tcp_source`. Nothing else: no GNSS node, no device patch, no taint.
