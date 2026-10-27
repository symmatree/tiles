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

- Core is 2026.10.2 (updated 2026-10-22, full backup `pre-2026.10.2` taken
  first), OS 18.3, Supervisor current. The Yellow's Zigbee radio was stuck
  behind a disk-full condition for months; both are resolved and `zha` loads,
  with no paired devices on it. All Z-Wave and Zigbee runs through the Hubitat
  hub.
- The Supervisor's `rpi_firmware_update_blocked` issue is permanent on this
  board: the CM4 bootloader EEPROM (1673458852, latest 1767975133) can only be
  flashed over USB with `rpiboot`; os-agent reports `eeprom_update_unavailable`
  for every Yellow. Nothing to do from software.
- Hubitat is on platform 2.5.2.139 (from 2.4.3.149, 2026-10-22; ~13 min of
  downtime, all 18 Z-Wave nodes present afterwards and reporting into HA). It
  no longer reports `isRadioUpdateNeeded`; the radio firmware is still 7.18.
  The hub's JSON endpoints and the update procedure belong in
  `fables/kb/Devices/Hubitat.md`, which is still a stub.
- HA's `/api/prometheus` is scraped into Mimir by the cluster's alloy-metrics
  (`job="integrations/homeassistant"`, ~3,000 series after drops). Before
  2026-10-27 the docs described this scrape, but nothing performed it, and
  Mimir held no `ha_*` series; history before that date is only in the
  appliance's own recorder database.
- **The browser door is live and in real use**, with two identities on the
  allowlist, verified end to end by someone other than the agent -- Google at
  the gate, then an HA local account. The two-prompt cost is handled
  client-side with a stored URL and autofill, so the idea of collapsing the
  layers (header auth, `--prompt=select_account`, installing hass-oidc-auth) is
  **closed, not deferred**. The only argument left for HA-side OIDC was
  revoking people centrally, which does not apply to this household.
- The browser door has one trap: Home Assistant's frontend is a PWA, and once
  the oauth2-proxy session expires its service worker keeps requesting in the
  background. With `--skip-provider-button`, each of those requests started a
  login and overwrote the single CSRF cookie, so the Google callback failed
  with `CSRF token mismatch` and then a 500. #865 (merged 2026-10-22) switches
  the gate to per-request CSRF cookies and makes the frontend's background
  paths API routes (401, no login). It takes effect when the `prod` tag moves
  past it; until then the workaround is clearing the site's data in the
  browser, or an incognito window.
- The companion-app door (mutual TLS) is live: #812 merged, Deployment
  `homeassistant-tls` (two ghostunnel `v1.11.4-distroless` hops) on
  LoadBalancer `10.0.130.2:8443`, `homeassistant-tls.tiles.symmatree.com` a
  CNAME to `lhitw`. `10.0.130.2` comes from `lb-static-pool`
  (`charts/cilium-config`, label-selected), announced over L2; the lease is held
  by acebase. Verified: no client cert is refused at the handshake; the
  `seth-pixel` cert gets 200 on `/` and 401 on `/api/`; a phone off the LAN
  gets `ERR_BAD_SSL_CLIENT_AUTH_CERT`, and the gateway logs the rejected
  handshake from the SNAT address, so the outside path reaches it. Not tested:
  a wrong-CA cert, an expired cert, websockets. What is left is the Android
  enrolment (PKCS#12 from the device Secret), which needs a device in hand.
- Five of six Zooz motion sensors are battery-dead and feed `entity_controller`.
  Tracked as `ha-config#4`; the surrounding maintenance plan is `#5`-`#10`.
  `ha-config#12` fixed a separate fault found the same way: both the garage and
  basement controllers were pointing at a ratgdo entity id that no longer
  exists.
- First pass of the entity sweep is done. Of 2709 registry entries: 1391
  disabled (1387 of those by the integration itself, which is routine -- only 4
  are deliberate), 0 orphaned with no state, 470 `restored`, 19 `unavailable`,
  77 `unknown` and 10 unmanageable. Most of the `unknown` pile is
  stateless-by-design (buttons, Hue scenes). The `restored` pile is where the
  real findings were.
- `konnected` and `songpal` show `not_loaded` because both config entries are
  ignored discoveries (`source: ignore`); that is their normal state, not a
  failure. `roborock` authenticated again from 2026-10-15 on. `xbox` fails
  against the Nabu Casa account-link endpoint (400) and is the one open
  Repair; the operator has decided it is not worth re-linking. Deleting the
  entry would clear the Repair.
- `ha-config#11` (the migrated `http:` block) and `#12` (the ratgdo id) are
  merged, pulled onto the appliance and applied by a Core restart; the
  `yaml_still_present_after_migration` repair has cleared.

## Technique

The REST API covers states and services. Most things worth asking are on the
websocket API, which is also the only working route to the Supervisor from
outside -- `POST /api/hassio/<path>` returns **401** even with an admin token,
so use the websocket `supervisor/api` passthrough with `endpoint` and `method`
instead.

The shortest route is SSH. The SSH add-on listens on port 22 (22222 is
refused) and accepts the operator's key, as `root`. From there the `ha` CLI
covers Supervisor, OS, backups and Core updates (`ha backups new --name ...`,
`ha core update --version ...`, `ha resolution info`), and the Supervisor
proxies Core's REST API without a long-lived token:
`curl -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/core/api/states`.
`/config/.storage/*` is readable directly (config entries, the repairs
registry, the entity registry); `jq` is installed.

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

**Landing a `ha-config` commit on the appliance is not a plain `git pull`.**
`/root/.gitconfig` carries a URL-scoped credential helper pointing at
`/usr/local/bin/gh`, which exists only in the VSCode Server add-on -- so from the
SSH add-on, where an agent lands, git cannot authenticate to GitHub and the pull
fails on "could not read Username". Either pull from the VSCode terminal, or move
the objects without credentials: `git bundle create f <ref> --not <box HEAD>`
locally, `scp` it over, then `git fetch /tmp/f refs/heads/<ref>:refs/remotes/origin/main`
and `git merge --ff-only`. Bundle the ref under a name the box can fetch -- a
bundle of `origin/main` carries `refs/remotes/origin/main`, which a
`refs/heads/main` refspec will not match.

A shallow sparse clone of `home-assistant/core` is at
`/home/jovyan/upstream/home-assistant-core`, pinned to the tag the appliance
runs. Re-pin after a core update. Reading the source beats guessing what a field
means from its name.

### Computing the buckets

HA's entity filters correspond to set operations over the registry and states,
and the distinctions matter because they have different causes:

| bucket | how to compute | what it means |
| --- | --- | --- |
| disabled | registry `disabled_by` set | split by value: `integration` is routine, `user` is deliberate |
| not provided | in registry, no state at all | orphaned registry entry |
| restored | state carries `attributes.restored` | the id is remembered but nothing supplies it |
| unavailable | state `unavailable`, not restored | the integration is present and says it cannot reach the thing |
| unknown | state `unknown` | often by design -- buttons and scenes have no state until used |
| unmanageable | has a state, no registry entry | YAML/template entities; cannot be edited from the UI |

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
- **A dead battery does not make a binary sensor unavailable -- it freezes it.**
  Several motion sensors here have been reporting `on` continuously since their
  cells died months ago, and HA shows them as ordinary and healthy. `unavailable`
  at least fails loudly; stuck-at-a-plausible-value does not, so a sweep has to
  look for staleness and not only for error states.

  What a frozen sensor does *not* do is drive anything: `entity_controller` arms
  on a state *transition*, which a frozen input can never emit again, so the
  timers expire normally. Verified against a real walk-through -- both delays
  fired to the second. The first version of this note claimed the opposite, from
  a single observation of `active_timer` that had another cause. Lost coverage,
  not an active fault.
- **A dead registry entry squats its entity id**, and the live entity that wants
  that id silently gets a `_2` suffix. So the obvious-looking id can be the dead
  one and the real device can be on the suffixed id. Check `attributes.restored`
  before trusting an id that appears in YAML, a dashboard or an external caller.
- **The upstream leg of the gate is testable from any pod** without a browser:
  send the appliance a request carrying `X-Forwarded-For`. 400 means it is
  rejecting proxied requests, 200 means the path works. This caught a wrong CIDR
  that four green CI runs did not.
