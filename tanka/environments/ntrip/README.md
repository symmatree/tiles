# NTRIP / RTKBase (prod acebase)

GNSS base + local NTRIP caster on bare-metal node **acebase**. Prod only (`cluster_name: tiles`); no acebase on test.

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

Pod runs privileged on acebase with hostPath `/dev/gnss`, PVC `/persist/rtkbase` (RTK data + `settings.conf`, bind-mounted into `/root/rtkbase/settings.conf` on boot), and systemd PID 1. NTRIP is exposed via LoadBalancer + external-dns; the web UI via Ingress + cert-manager (TLS only).

## Configuration: git is authoritative

[`settings.conf`](settings.conf) in this directory is the **single source of truth** for
`/root/rtkbase/settings.conf` on the device. The loop:

1. `main.jsonnet` stamps `std.md5(importstr 'settings.conf')` into the pod template as the
   `rtkbase-settings-hash` annotation.
2. Editing the file therefore changes the pod template, so Argo CD rolls the Deployment
   (`strategy: Recreate`, so a full stop/start -- see the interruption note below).
3. The `seed-settings` init container **unconditionally overwrites** the PVC copy from the
   ConfigMap on every start.

So: **edit here, merge, and the change lands on the next sync.** No manual step.

### The web UI is for inspection, not configuration

Anything changed through the RTKBase web UI writes to the PVC copy and **survives only until
the next pod restart** -- including restarts you did not ask for (node reboot, image update,
eviction). It will then silently revert to whatever is in git, with no warning in the UI.

If you want a setting to stick, put it in [`settings.conf`](settings.conf).

The one exception is `flask_secret_key`, which RTKBase generates on boot and writes back. It
is not in git and does not need to be; regenerating it only invalidates existing web sessions.

### Restarting interrupts data capture

`str2str_file` writes raw UBX to the PVC continuously (see
[`containers/rtkbase/README.md`](../../../containers/rtkbase/README.md)). A config change
restarts the pod, which **closes the in-progress capture file and starts a new one**. Existing
files are not lost, but a session in progress is cut short -- so if a long continuous
observation is being collected for a PPP solve, land the config change before or after it, not
during.

### History

This used to be a first-boot **seed**: the init container copied only `if [ ! -f ... ]`. Since
the hash annotation still rolled the pod on any edit, the result was a restart that applied
nothing, and every real change had to go through the web UI -- the on-box-override drift trap
[`docs/deployment-model.md`](../../../docs/deployment-model.md) exists to prevent (same class
as #48). Changed in the PR for coordinator#199.

## Authentication

**Web UI:** RTKBase ships with username `admin` and password `admin` ([upstream default](https://github.com/Stefal/rtkbase/)). Ingress adds HTTPS; no extra auth layer.

**NTRIP caster:** `gps` / `gps` (in [`settings.conf`](settings.conf); also in 1Password `{cluster}-ntrip-caster-auth`). Matches historical field clients (SW Maps, u-center, etc.).

## Operator follow-up (phase 5)

After first boot with the F9P attached: set fixed base coordinates, mountpoint `ATTIC`, RTCM message set, and verify NTRIP on `:2101`. See issue #488 and `facts/geospatial/sparkfun-gps-collection.md`.

## Dependencies

- [cert-manager](../../../charts/cert-manager/README.md), [external-dns](../../../charts/external-dns/README.md), [OnePassword operator](../../../charts/onepassword/README.md), [Cilium LB pool](../../../charts/cilium-config/)
- Acebase Talos GNSS patch and `dedicated=gnss:NoSchedule` taint (phase 1)
