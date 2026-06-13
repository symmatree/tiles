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

Pod runs privileged on acebase with hostPath `/dev/gnss`, PVC `/persist/rtkbase` (RTK data + persisted `settings.conf`, bind-mounted into `/root/rtkbase/settings.conf` on boot), and systemd PID 1. NTRIP is exposed via LoadBalancer + external-dns; the web UI via Ingress + cert-manager (TLS only).

## Authentication

**Web UI:** RTKBase ships with username `admin` and password `admin` ([upstream default](https://github.com/Stefal/rtkbase/)). Ingress adds HTTPS; no extra auth layer.

**NTRIP caster:** `gps` / `gps` (in [`settings.conf`](settings.conf); also in 1Password `{cluster}-ntrip-caster-auth`). Matches historical field clients (SW Maps, u-center, etc.).

## Operator follow-up (phase 5)

After first boot with the F9P attached: set fixed base coordinates, mountpoint `ATTIC`, RTCM message set, and verify NTRIP on `:2101`. See issue #488 and `facts/geospatial/sparkfun-gps-collection.md`.

## Dependencies

- [cert-manager](../../../charts/cert-manager/README.md), [external-dns](../../../charts/external-dns/README.md), [OnePassword operator](../../../charts/onepassword/README.md), [Cilium LB pool](../../../charts/cilium-config/)
- Acebase Talos GNSS patch and `dedicated=gnss:NoSchedule` taint (phase 1)
