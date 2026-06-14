# MAVProxy ground proxy (prod acebase)

Always-on MAVLink hub on bare-metal node **acebase**: ELRS backpack UDP in, NTRIP RTCM to the drone, TCP out for Mission Planner.

Prod only (`cluster_name: tiles`); co-located with [ntrip](../ntrip/README.md) on site LAN.

## Endpoints

| Service | Address | Notes |
|---------|---------|-------|
| MAVLink UDP (from Boxer backpack) | acebase host `:14550/udp` | `hostNetwork`; receives subnet broadcast |
| Mission Planner TCP | `mavproxy.tiles.symmatree.com:5760` | LoadBalancer + external-dns |
| NTRIP corrections source | `ntrip.tiles.symmatree.com:2101/ATTIC` | Same caster as [ntrip](../ntrip/README.md) |

Both hostnames resolve to private **10.x** addresses on site LAN. Mission Planner: **TCP**, system ID **254**.

## Architecture

- **Image:** [`containers/mavproxy/`](../../../containers/mavproxy/)
- **Build:** [`.github/workflows/build-mavproxy.yaml`](../../../.github/workflows/build-mavproxy.yaml)
- **Tanka:** [`main.jsonnet`](main.jsonnet)
- **Argo CD:** [`application.helm.yaml`](application.helm.yaml) (prod only)

Pod uses **hostNetwork** on acebase (privileged namespace, `dedicated=gnss` toleration) so ELRS backpack UDP broadcast on `:14550` reaches the proxy. MAVProxy runs with **`--daemon`** and **`--nowait`** as GCS **sysid 255**. NTRIP is configured via **`$HOME/.mavproxy/mavinit.scr`** written by the container entrypoint. No **liveness** probe -- k8s must not restart this hub. Readiness is **`kill -0 1`** only (never TCP `:5760`; `tcpin` accepts one Mission Planner client).


## Operator notes

- Boxer backpack GCS target is learned from MAVLink heartbeats; no static destination in backpack UI.
- Do not connect Mission Planner directly to the backpack while this proxy is running.
- After first image build, Argo CD needs `ghcr.io/symmatree/tiles/mavproxy:main` available.

## Dependencies

- [external-dns](../../../charts/external-dns/README.md), [OnePassword operator](../../../charts/onepassword/README.md), [Cilium LB pool](../../../charts/cilium-config/)
- [ntrip](../ntrip/README.md) caster on acebase
- Acebase node on site LAN (same broadcast domain as `boxer-txbp`)
