# NTRIP / RTKBase (prod acebase)

GNSS base + local NTRIP caster on bare-metal node **acebase**. Prod only (`cluster_name: tiles`); no acebase on test.

## Endpoints

| Service | URL | Auth |
|---------|-----|------|
| NTRIP caster | `ntrip.tiles.symmatree.com:2101` / mountpoint `ATTIC` | `{cluster}-ntrip-caster-auth` in 1Password |
| Admin web UI | `https://ntrip-admin.tiles.symmatree.com` | `{cluster}-ntrip-admin` in 1Password (username `admin`) |

## Architecture

- **Image:** [`containers/rtkbase/`](../../../containers/rtkbase/)
- **Terraform secrets:** [`tf/modules/k8s-cluster/ntrip.tf`](../../../tf/modules/k8s-cluster/ntrip.tf)
- **Tanka:** [`main.jsonnet`](main.jsonnet)
- **Argo CD:** [`application.helm.yaml`](application.helm.yaml) (prod only: `cluster_name == tiles`)

Pod runs privileged on acebase with hostPath `/dev/gnss`, PVC `/persist/rtkbase`, and systemd PID 1. NTRIP is exposed via LoadBalancer + external-dns; the web UI via Ingress + cert-manager.

## Web UI authentication

RTKBase uses a **single built-in user** with username **`admin`** (hardcoded in upstream Flask app). The password is stored as a werkzeug hash in `settings.conf` (`web_password_hash`); upstream default is the literal password **`admin`** ([Stefal/rtkbase README](https://github.com/Stefal/rtkbase/)).

Unlike Apprise, there is no nginx/basic-auth sidecar. Ingress provides TLS only; the app login form is the gate.

Terraform generates a random admin password and stores it in 1Password as a **login** item (`tiles-ntrip-admin`, username `admin`, URL `https://ntrip-admin.tiles.symmatree.com`) so the browser extension can autofill. The 1Password operator syncs it into the cluster; [`rtk-base-on-bootup`](../../../containers/rtkbase/rtk-base-on-bootup) writes `new_web_password` into persisted `settings.conf` before `rtkbase_web` starts, and RTKBase hashes it on service start.

## NTRIP caster authentication

Caster credentials live in `settings.conf` under `[local_ntrip_caster]` as plain `local_ntripc_user` / `local_ntripc_pwd`. Terraform creates `{cluster}-ntrip-caster-auth` (username `gps`, random password) for client reference. Historical field setup used `gps`/`gps`; change via the web UI or update clients after deploy.

## Operator follow-up (phase 5)

After first boot with the F9P attached: set fixed base coordinates, mountpoint `ATTIC`, RTCM message set, and verify NTRIP on `:2101`. See issue #488 and `facts/geospatial/sparkfun-gps-collection.md`.

## Dependencies

- [cert-manager](../../../charts/cert-manager/README.md), [external-dns](../../../charts/external-dns/README.md), [OnePassword operator](../../../charts/onepassword/README.md), [Cilium LB pool](../../../charts/cilium-config/)
- Acebase Talos GNSS patch and `dedicated=gnss:NoSchedule` taint (phase 1)
