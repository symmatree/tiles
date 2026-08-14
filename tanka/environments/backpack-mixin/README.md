# Backpack mixin

Grafana dashboard for the **ELRS TX backpack's WiFi link** -- the backpack-to-AP
hop that bridges house WiFi UDP to the ELRS RF uplink, and the least reliable link
in the RTK corrections path (coordinator
[#99](https://github.com/symmatree/coordinator/issues/99),
[#190](https://github.com/symmatree/coordinator/issues/190)).

Prod only (`cluster_name: tiles`) -- the backpack is site hardware.

## Metrics it needs

Produced by the `backpack-mavlink` Probe in the
[mavproxy](../mavproxy/README.md) environment, which has Alloy scrape the
backpack's `GET /mavlink` endpoint every 30s under `job="backpack"`, through the
shared json_exporter in the `alloy` namespace:

- `up` -- scrape success; doubles as "is the backpack on the network".
- `backpack_wifi_rssi_dbm`, `backpack_wifi_reconnects_total`,
  `backpack_uptime_milliseconds`.
- `backpack_mavlink_enabled`, `backpack_mavlink_packets_{up,down}_total`,
  `backpack_mavlink_{drops_down,overflows_down}_total`.
- `backpack_wifi_link_info{ssid,bssid}`, `backpack_mavlink_gcs_info{gcs}`.

The job label comes from the Probe's `jobName`; override `_config.backpackSelector`
if you scrape it some other way.

## Reading the dashboard

- **Reconnects rising while still reachable** is the WiFi-robustness patch working:
  the firmware rode out a `WL_CONNECTION_LOST` instead of stranding on its own AP
  until a power-cycle. On stock firmware each of those was a silent RTK failure.
- **RSSI** has been measured at -75..-79 dBm at close range (esp8285 trace antenna
  next to the 1 W VTX). This series is what placement / antenna / Nomad-hardware
  changes have to move.
- **`up` gaps are expected.** The backpack is only on WiFi when the radio is
  powered and Telem mode = WiFi; read "reachable share" against how long the radio
  was actually on, not as an SLO.
- **`gcs`** should be acebase (`10.0.99.14`, mavproxy). A different address would
  mean some other GCS latched the backpack's MAVLink stream.
- **`drops_down`** is a counting artifact of one global MAVLink sequence across
  interleaved sources, not measured loss; `overflows_down` is the real
  link-capacity signal.

## No alerts

Deliberate: the backpack's resting state is off, so an availability alert would
fire almost continuously. This mixin is for trending across hardware changes.

## Layout

- [`main.jsonnet`](main.jsonnet) -- tiles wiring (Grafana folder, tags).
- [`mixin/`](mixin/) -- the mixin proper (config, dashboard).
- [`application.helm.yaml`](application.helm.yaml) -- Argo CD Application (prod only).
