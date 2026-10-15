# Handoff: Home Assistant

Session notes for whoever picks up Home Assistant next. **Not documentation.**
Pointers, technique, and the current state of play -- things that are true today
and may not be next month.

Anything durable that gets learned belongs in the real docs instead, and this
page should shrink when that happens:

| what | where it lives |
| --- | --- |
| the system: appliance, radios, integrations, auth | `facts/SmartHome/Smart home design.md` (private) |
| where it is going | `facts/SmartHome/Smart home vision.md` (private) |
| the Hubitat hub, and its JSON endpoints | `fables/kb/Devices/Hubitat.md` |
| the remote-access perimeter and its traps | [remote-access.md](../remote-access.md) |
| the gate chart | [charts/homeassistant](../../charts/homeassistant/README.md) |
| the certificate push | [charts/static-certs](../../charts/static-certs/README.md) |
| maintenance and monitoring work | issues in `symmatree/ha-config` (private) |

## State of play

- Core is current. The Yellow's Zigbee radio was stuck behind a disk-full
  condition for months; both are resolved and `zha` loads, with no paired
  devices on it. All Z-Wave and Zigbee runs through the Hubitat hub.
- The browser door is live. The companion-app door (mutual TLS) is built but
  unmerged, waiting on a hands-on test with a device.
- Five of six Zooz motion sensors are battery-dead and feed `entity_controller`.
  Tracked as `ha-config#4`; the surrounding maintenance plan is `#5`-`#10`.
- A one-time exhaustive sweep for not-responding and misconfigured entities is
  agreed but not started -- deliberately after the pending upgrades and Repairs
  settle. The point is enumeration over sampling, since these signals do not
  collect anywhere in the UI.
- `konnected` and `songpal` not loaded; `roborock` fails on credentials; `xbox`
  fails against its account-link endpoint. All predate the current work.
- Hubitat's own Z-Wave radio reports `isRadioUpdateNeeded: true`.
- `ha-config#11` removes the migrated `http:` block; `#4`-`#10` are the
  maintenance and monitoring plan.

## Technique

The REST API covers states and services. Most things worth asking are on the
websocket API, which is also the only working route to the Supervisor --
`POST /api/hassio/<path>` returns **401** even with an admin token, so use the
websocket `supervisor/api` passthrough with `endpoint` and `method` instead.

| want | how |
| --- | --- |
| integrations, and why one failed | `config_entries/get` -- `state` and `reason` |
| is a YAML-configured component loaded | `get_config` -> `components` |
| entities, platforms, disabled flags | `config/entity_registry/list` |
| devices and models | `config/device_registry/list` |
| current values | `get_states` |
| recent warnings and errors | `system_log/list` |
| disk, backups, add-ons, host actions | `supervisor/api` |
| backup schedule and retention | `backup/config/info` |
| outstanding Repairs | `repairs/list_issues` |
| the live HTTP config (TLS paths, trusted proxies) | `http/config` -- see below |

`homeassistant.restart` restarts Core only (~6 min); `/host/reboot` through the
passthrough reboots the appliance, which is what a radio firmware change wants.
A restart call returns **504** because Core tears down its own HTTP server
mid-request -- that is success.

**HTTP config is no longer YAML.** Home Assistant migrated it to storage in
2026.10; `configuration.yaml`'s `http:` block is ignored from that point and
stops working in 2027.2.0. `http/config` returns `stable`, `pending`,
`revert_at` and `active_config_type` -- a freshly migrated or edited config is
staged as a *pending trial* and reverts after five minutes unless promoted, so
check `active_config_type` rather than assuming an edit stuck.

A shallow sparse clone of `home-assistant/core` is at
`/home/jovyan/upstream/home-assistant-core`, pinned to the tag the appliance
runs. Re-pin after a core update. Reading the source beats guessing what a field
means from its name.

## Things that have produced wrong answers here

Kept on this page because they are about method rather than about the system.

- **A config entry's `reason` is a snapshot of its last setup attempt.** After
  the underlying cause is fixed it keeps the old message until the entry is
  reloaded or the host restarts. "Still broken" may be a stale string.
- **YAML-configured components never appear in `config_entries/get`.** Checking
  there will tell you a loaded integration is missing. Use `components`.
- **The Zigbee coordinator's `sw_version` is only written when the integration
  sets up**, so after a failed setup it is stale or `None`. The radio firmware
  `update.*` entity's `installed_version` is authoritative.
- **`automatic_backups_configured` governs nothing** -- it is commented
  `# only used by frontend` in core and was back-filled by a store migration from
  whether a backup password existed. `schedule.recurrence` is what schedules.
- **Querying right after a restart** returns a snapshot full of
  `setup_in_progress`, which reads like a pile of failures. Wait for
  `get_config` to report `state: RUNNING`, then give it a minute.
- **`last_changed` on a stale entity reflects the last HA restart**, not the last
  time the device reported. Restored states look fresh. Go to the hub for
  recency.
- **Dump a set before filtering it.** `system_log/list` rows carry a `count` and
  a `message` *list*; slicing that list, or grepping for a word that also appears
  in routine lines, has produced wrong conclusions here more than once.
- **The upstream leg of the gate is testable from any pod** without a browser:
  send the appliance a request carrying `X-Forwarded-For`. 400 means it is
  rejecting proxied requests, 200 means the path works. This caught a wrong CIDR
  that four green CI runs did not.
