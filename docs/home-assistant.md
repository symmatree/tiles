# Home Assistant -- working notes and handoff

For whoever owns Home Assistant next. This is the operational half: how to reach
it, how to ask it questions, and the things that are easy to get wrong. It is
deliberately thin on inventory, because **this repository is public** -- the
system description and the direction live in the private `facts` vault:

- `facts/SmartHome/Smart home design.md` -- current state, integration inventory
- `facts/SmartHome/Smart home vision.md` -- where it is going
- `facts/SmartHome/homeassistant.md` -- the appliance
- `fables/kb/Devices/Hubitat.md` -- the radio hub

What lives here in tiles: the remote-access perimeter
([remote-access.md](remote-access.md)), the gate chart
([charts/homeassistant](../charts/homeassistant/README.md)), the certificate push
([charts/static-certs](../charts/static-certs/README.md)), and this page.

## Reaching it

Home Assistant is **not** a workload in this cluster. It is an appliance on the
house LAN, reachable from any pod by the name on its certificate. The cluster
fronts it with two doors, both documented in
[remote-access.md](remote-access.md); the appliance itself stays directly
reachable on the LAN for the machine clients that cannot pass an identity
challenge.

Operator access for an agent is a **long-lived access token**. Note that Home
Assistant has no per-token permissions: a token inherits the full rights of the
user who created it, and per-entity ACLs do not exist. The documented workaround
is a dedicated non-admin user. Treat the token as equivalent to that account --
among other things, `backup/config/info` returns the backup encryption password
in cleartext to any admin token.

## Asking it questions

The REST API covers states and services. **Everything interesting is on the
websocket API**, including the only working route to the Supervisor:

| want | how |
| --- | --- |
| integrations and why one failed | `config_entries/get` -- read `state` and `reason` |
| is a YAML component loaded | `get_config` -> `components` list |
| entities, platforms, disabled flags | `config/entity_registry/list` |
| devices, models, `sw_version` | `config/device_registry/list` |
| current values | `get_states` |
| recent warnings and errors | `system_log/list` |
| disk, backups, add-ons, host actions | `supervisor/api` with `endpoint` + `method` |
| backup schedule and retention | `backup/config/info` |

`POST /api/hassio/<path>` returns **401** even with an admin token -- the HTTP
Supervisor proxy is not available that way. Use the websocket `supervisor/api`
passthrough instead, e.g. `endpoint: /host/info`, `endpoint: /backups`,
`endpoint: /host/reboot` with `method: post`.

`homeassistant.restart` restarts Core only (~6 min). `/host/reboot` through the
passthrough reboots the appliance, which is what a radio firmware change wants.
A restart call returns **504** because Core tears down its own HTTP server
mid-request; that is success, not failure.

## The Hubitat hub answers without authentication

All Z-Wave and Zigbee devices are mediated by a Hubitat hub, not by the
appliance's own radio. Its local UI is a Vue SPA, so scraping pages gets you a
7 KB shell -- but the JSON endpoints behind it respond unauthenticated:

| endpoint | content |
| --- | --- |
| `/hub2/devicesList` | every device the hub knows, nested under `.devices[].data`, with `lastActivity`, `disabled`, `type`, `dni`, `zigbeeId` |
| `/hub/zwaveDetails/json` | the Z-Wave node table: `nodeId`, `nodeState`, `deviceId`, `deviceName`, `msgCount`, `lastTime`, `neighbors`, plus radio flags |
| `/hub2/appsList` | installed apps, including the Maker API instances |
| `/hub/details/json` | hub identity and platform version |
| `/hub2/hubData` | hub summary |

Note the `/json` suffix: `/hub/zwaveDetails` alone is a 404 and `/hub/zwaveInfo`
is just the SPA shell. Guessing endpoint names wastes time; these five are the
ones that work.

**To find a device the hub knows about but cannot talk to**, do not trust
`nodeState` -- it reads `OK` for nodes that have never exchanged a message. The
liveness signals are `msgCount` and `lastTime` in `/hub/zwaveDetails/json`, and
`lastActivity` per device in `/hub2/devicesList`. A node with `msgCount: 0`,
`lastTime: null` and a stale `lastActivity` is present, paired, and dead.

A node with no `deviceId` is a ghost -- a pairing that left a Z-Wave node behind
with no device attached. Worth checking when a device "should" exist and does
not appear anywhere.

## Traps, each of which cost a wrong conclusion

- **Hubitat exposes no `switch.*` entities.** Every switchable device it
  mediates arrives as `light.*`, including models named "Smart Switch". Anything
  driving one should call `homeassistant/turn_on`, which works regardless of
  domain, rather than `switch/turn_on`.
- **HA reports a dead Hubitat device as available.** Entities for sensors that
  have not reported in months still show a state rather than `unavailable`. HA's
  availability is not a liveness signal for anything behind Hubitat; go to the
  hub for that.
- **The gate's `trusted_proxies` is the node subnet, not the pod CIDR.** Cilium
  masquerades pod traffic leaving the cluster to the node's address. This is the
  opposite of oauth2-proxy's own `--trusted-proxy-ip`, which is correctly the pod
  CIDR because it governs the inbound hop. See
  [remote-access.md](remote-access.md#upstreams-outside-the-cluster).
- **YAML-configured components never appear in `config_entries/get`.** Checking
  for config entries will tell you a YAML integration is missing when it is
  loaded fine. Use the `components` list from `get_config`.
- **The Zigbee coordinator's `sw_version` is unreliable.** It is only written
  when the integration sets up, so after a failed setup it reports a stale
  version or `None`. The authoritative value is the radio firmware `update.*`
  entity's `installed_version`.
- **A config entry's `reason` is a snapshot of its last setup attempt.** After
  fixing the underlying cause it keeps the old message until the entry is
  reloaded or the host restarts -- so "still broken" may just be a stale string.
- **`automatic_backups_configured` governs nothing.** It is commented
  `# only used by frontend` in core, and was back-filled by a store migration
  from whether a backup password existed. What actually schedules a backup is
  `schedule.recurrence`.

## Reading the source rather than guessing

A shallow sparse clone of `home-assistant/core` lives at
`/home/jovyan/upstream/home-assistant-core`, pinned to the tag matching whatever
the appliance runs, with `git sparse-checkout` narrowed to the components of
interest. Re-pin it after a core update. Widening the checkout is cheaper than
guessing at what a field means from its name.

## Verification habits that have paid off

- The gate's upstream leg is testable from any pod without a browser: send a
  request to the appliance carrying `X-Forwarded-For`. A 400 means the appliance
  is rejecting proxied requests; a 200 means the forwarded path works. This
  caught a wrong CIDR that four green CI runs did not.
- After a restart or reboot, wait for `get_config` to report `state: RUNNING`
  and then give it a minute. Querying immediately returns a snapshot full of
  `setup_in_progress`, which reads like a pile of failures and is not.
- Dump a set before filtering it. `system_log/list` rows carry a `count` and a
  `message` **list**; slicing that list, or grepping for a keyword that also
  appears in routine lines, has produced wrong conclusions here more than once.

## Open threads

- The companion-app door (mutual TLS) is built but unmerged, waiting on a
  hands-on test with a device.
- `konnected` and `songpal` are not loaded; `roborock` fails on credentials;
  `xbox` fails against its account-link endpoint. All predate the current work.
- The Hubitat Z-Wave radio reports `isRadioUpdateNeeded: true`, separate from the
  appliance's own Zigbee radio.
- Several add-ons and devices have updates pending.
