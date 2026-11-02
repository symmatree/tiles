# MAVProxy ground proxy (prod acebase)

Two always-on MAVLink proxies on bare-metal node **acebase**, one per radio link to the drone:

- **`mavproxy-mlrs`** -- the mLRS link: a RadioMaster Ranger on USB-C (`/dev/mlrs`) to the RP4TD on
  the FC's SERIAL7. It carries the **NTRIP RTCM** up and the telemetry down, and logs it.
- **`mavproxy`** -- the ELRS backpack link (UDP in). **Logging only** since 2026-11-02: no NTRIP.

Prod only (`cluster_name: tiles`); co-located with [ntrip](../ntrip/README.md) on site LAN.

## Endpoints

| Service | Address | Notes |
|---------|---------|-------|
| MAVLink UDP (from Boxer backpack) | acebase host `:14550/udp` | `hostNetwork`; receives subnet broadcast |
| Mission Planner TCP, ELRS link | `mavproxy.tiles.symmatree.com:5760` | LoadBalancer + external-dns |
| Mission Planner TCP, mLRS link | `mavproxy-mlrs.tiles.symmatree.com:5770` | LoadBalancer + external-dns |
| NTRIP corrections source | `ntrip.tiles.symmatree.com:2101/ATTIC` | Same caster as [ntrip](../ntrip/README.md) |

Both hostnames resolve to private **10.x** addresses on site LAN. Mission Planner: **TCP**, system ID **254**.

## Architecture

- **Image:** [`containers/mavproxy/`](../../../containers/mavproxy/)
- **Build:** [`.github/workflows/build-mavproxy.yaml`](../../../.github/workflows/build-mavproxy.yaml)
- **Tanka:** [`main.jsonnet`](main.jsonnet)
- **Argo CD:** [`application.helm.yaml`](application.helm.yaml) (prod only)

The ELRS pod uses **hostNetwork** on acebase (privileged namespace, `dedicated=gnss` toleration) so ELRS backpack UDP broadcast on `:14550` reaches the proxy. MAVProxy runs with **`--daemon`** and **`--nowait`** as GCS **sysid 255**. NTRIP is configured via **`$HOME/.mavproxy/mavinit.scr`** written by the container entrypoint. No **liveness** probe -- k8s must not restart this hub.

The mLRS pod is an ordinary pod pinned to acebase (same toleration), **privileged** for the host
device node like the ntrip pod's `/dev/gnss`. `/dev/mlrs` is a udev symlink from
[`tf/nodes/patches/acebase-gnss.yaml`](../../../tf/nodes/patches/acebase-gnss.yaml) on the
Ranger's CP2102 (`10c4:ea60`, `cp210x`), 115200 baud to match the module's `Tx Ser Baudrate`.
It runs `--streamrate=-1` (sends no `REQUEST_DATA_STREAM`; the FC pins MAV4's rates). Its
tlog-split instance (`tlog-split-mlrs`, UDP 5762) writes to `ground-tlogs/mlrs/`, because both
links cut at the same disarm and would otherwise produce identically named files. Readiness is **`kill -0 1`** only (never TCP `:5760`; `tcpin` accepts one Mission Planner client).


## Backpack link health (`backpack-mavlink` Probe)

One `Probe` CR in this namespace, unrelated to the proxy process: it has Alloy
scrape the Boxer backpack's own status endpoint so its WiFi link is trendable
over time (coordinator
[#190](https://github.com/symmatree/coordinator/issues/190),
[#99](https://github.com/symmatree/coordinator/issues/99)). The patched backpack
firmware reports link health **only** on `GET http://10.0.6.120/mavlink` -- it is
never in the MAVLink channel, so mavproxy cannot see it.

| Piece | Where |
|-------|-------|
| `backpack-mavlink` Probe | **here**: target `http://10.0.6.120/mavlink`, module `backpack`, every **30s**, `job="backpack"` |
| json_exporter (the prober) | shared, in the `alloy` namespace -- `json-exporter.alloy.svc:7979`, deployed by the [Alloy app](../../../charts/argocd-applications/templates/README-alloy.md) alongside blackbox |
| module `backpack` (JSON -> metrics mapping) | with the prober, in `alloy-application.yaml` |

Metrics: `backpack_wifi_rssi_dbm`, `backpack_wifi_reconnects_total`,
`backpack_uptime_milliseconds`, `backpack_mavlink_{enabled,packets_up_total,packets_down_total,drops_down_total,overflows_down_total}`,
and the info series `backpack_wifi_link_info{ssid,bssid}` /
`backpack_mavlink_gcs_info{gcs}`. Dashboard: [backpack-mixin](../backpack-mixin/README.md).

- **30s, not faster.** The backpack is a single-threaded esp8285 on a marginal
  link; the 5s polling used during bring-up is a manual, short-lived thing.
- **`up == 0` is normal.** The endpoint only answers when the radio is powered
  and Backpack Telem mode = WiFi. json_exporter returns 503 when it cannot fetch,
  so the scrape simply fails -- that gap is the availability signal, not an error.
- The target address is a `backpack_mavlink_url` app setting in
  [`application.helm.yaml`](application.helm.yaml).

## Operator notes

- Boxer backpack GCS target is learned from MAVLink heartbeats; no static destination in backpack UI.
- Do not connect Mission Planner directly to the backpack while this proxy is running.
- After first image build, Argo CD needs `ghcr.io/symmatree/tiles/mavproxy:main` available.

## Dependencies

- [external-dns](../../../charts/external-dns/README.md), [OnePassword operator](../../../charts/onepassword/README.md), [Cilium LB pool](../../../charts/cilium-config/)
- [ntrip](../ntrip/README.md) caster on acebase
- Acebase node on site LAN (same broadcast domain as `boxer-txbp`)
