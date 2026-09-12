# Analysis notebooks -- pattern and authoring guide

Standing analysis of deployed software as Jupyter notebooks: deterministic data
collection plus a rendered judgment surface for both humans and agents. The LLM
does the thinking; the notebook does the data collection -- instead of an agent
re-deriving "check mimir health" through dozens of ad-hoc tool calls each
session, it reads one artifact whose rote layer is mechanized and re-runnable.
Tracking issue: [#644](https://github.com/symmatree/tiles/issues/644). Deeper
design rationale lives in the facts KB (`notebook-analysis/design-intent.md`,
esp. section 2); the first exemplar of the pattern is `flight-analysis.ipynb` in
the fables repo.

Two ideas justify the form (design-intent.md section 2):

- **Notebook-as-UI (rendering-surface).** A cell is *both* source (re-runnable,
  diffable) and rendered output (the human sees the chart) -- one object, two
  views, no "diagram stale relative to its code" seam. It lives **outside any one
  agent's transcript scope**, shared like a git working tree: many agents, you,
  and VS Code all point at the same `.ipynb`. The headless render is
  self-validating -- a broken cell fails the run, so the loop closes without a
  human in it.
- **Notebook-as-dense-source-of-tokens (agent-economics).** You are not burning
  40k tokens of context re-deriving log-scraping mechanics so 2k tokens of
  judgment can happen at the end; you spend almost no context on the mechanics
  and hand the agent a tight, pre-digested artifact to reason about. Higher-order
  context in, better judgment out, cheaper -- and it checks the *same* things
  every time instead of subtly different ones.

Where this sits relative to alerting: **alerting is the push path** (something is
wrong -> tell me); **these notebooks are the pull path** (something seems off, or
I'm changing something -> show me everything densely). Same underlying capability
viewed from the two ends.

Current notebooks: [`notebooks/`](../notebooks/) -- `mimir-health.ipynb`,
`mimir-usage.ipynb`, `mimir-nolgtm.ipynb`, `loki-health.ipynb`,
`loki-usage.ipynb`, `loki-nolgtm.ipynb`, `alloy-health.ipynb`,
`alloy-nomon.ipynb`, `raconteur-health.ipynb`, `proxmox-health.ipynb`,
`metal-health.ipynb`, `cilium-health.ipynb`, sharing
[`nb_capture.py`](../notebooks/nb_capture.py). Roadmap for the rest of the stack:
see **Component roadmap** below.

## The shape

Every notebook follows the same cell skeleton:

1. **parameters** (papermill-tagged): endpoints, tenant, lookback, `debug`,
   `capture_file` (replay), `output_dir`.
2. **setup**: imports, `Capture` + API helper construction.
3. **assumptions**: verify the instruments before trusting any reading. A
   violated load-bearing assumption raises ("unassessable") -- never a false
   green or a false red. Non-fatal gaps degrade only their own section.
4. **capture**: fetch the *complete* raw observation up front, each API call
   recorded under a stable name, so a broken analysis cell cannot cost the
   snapshot. Capture is authoritative (the past cannot be re-queried); analysis
   below it is disposable inference over the capture.
5. **analysis sections**: tables and plots reading only through the capture.
6. **summary**: assumption ledger first, then findings vs explicit thresholds.
7. **agent stats**: one consolidated JSON, assumptions leading, for
   programmatic consumption.

Replay: `capture_file` re-analyzes a saved capture with no network or cluster
access -- old incidents can be re-analyzed with an improved notebook.

## Placement rule

A notebook lives in the repo you would have to touch when its subject changes.
Mimir is deployed by this repo and there is exactly one deployment per cluster,
so its notebooks live here: the notebook's constants (URLs, tenants, limits)
are this repo's constants, and a config change plus its notebook re-check can
land as one reviewable PR. A flight log is a fables subject, so
flight-analysis lives in fables. If a notebook ever generalizes across many
deployments it graduates to shared tooling with per-deployment parameters --
a different problem; revisit placement then.

## Per-software decision tree

- **One health notebook by default.** General status, using the monitoring
  stack normally -- no defensive error handling for the stack itself. If
  monitoring is broken, we fix that first.
- **Add a usage/capacity notebook** when tenancy, limits, or cardinality is
  its own conversation (mimir).
- **Add a no-LGTM notebook only when the software cannot assume the
  monitoring stack works** -- i.e. it *is* the monitoring stack (mimir, loki,
  alloy, grafana). It may use only instruments outside the stack (kube API,
  direct HTTP probes); the subject may appear as a labeled system-under-test
  smoke check, never as an instrument. A no-LGTM notebook still has to earn its
  keep with real checks (alloy-nomon caught the #656 singleton crashloop kube-only)
  -- it is not a licence for boilerplate; see the anti-LARP rule below.

## Component roadmap

The pattern repeats across the stack. Each row is a tracking issue with the
component specifics and query hints already worked out, so a future agent does
not have to rediscover them. **Edge-host** rows (Synology, Proxmox) are ordinary
host-health notebooks -- they *assume LGTM works* and read the metrics/logs the
host already ships. Their question is "is this host healthy," not "is the data
arriving": collection-liveness is a single line in the assumptions cell (one
fresh series, one recent log line), and if that trips it is the cue for deeper
debugging, not the premise of the notebook.

| Subject | Notebooks | Status | Issue |
| --- | --- | --- | --- |
| Mimir | health, usage, no-LGTM | built | [#644](https://github.com/symmatree/tiles/issues/644) |
| Loki | health, usage, no-LGTM | built | [#649](https://github.com/symmatree/tiles/issues/649) |
| Grafana | health, no-monitoring | planned | [#650](https://github.com/symmatree/tiles/issues/650) |
| Alloy (head-end collection) | health, no-monitoring | built | [#651](https://github.com/symmatree/tiles/issues/651) |
| Synology / Raconteur (edge host) | host health: SMART/disk errors, temps, fans, resource pressure | built | [#652](https://github.com/symmatree/tiles/issues/652) |
| Proxmox LXC (edge host) | host health: hwmon temps, NVMe, throttle, host disk I/O, root LV | built | [#653](https://github.com/symmatree/tiles/issues/653) |
| Bare-metal Talos (lancer, acebase) | host health: CPU/iGPU/storage temps, throttle, resources, `/var`, talos-`<rand>` gate | built | [#653](https://github.com/symmatree/tiles/issues/653) |
| Cilium / cluster-network | health: node reachability, agent/endpoint health, datapath pressure (BPF/CT/NAT maps, drops), IPAM, mixin-alert state | built | -- |

The **Cilium** notebook is a plain health notebook (cilium self-metrics are scraped into
Mimir, so it assumes the stack works, like the edge-host rows). Its node-reachability section
is grounded in the `CiliumUnreachableNodes` incident of 2026-07-25: a bare-metal reboot left
stale cilium-health prober state falsely reporting acebase/lancer host-unreachable while the
overlay path stayed healthy. It distinguishes that residue (host-path fail + overlay-path OK +
recent reboot -> restart the agent) from a real partition (both paths fail), and reads the
deployed cilium-mixin alert states rather than re-inventing their thresholds -- see
[bare-metal-nodes.md](bare-metal-nodes.md#node-hostnames-and-dhcp-less-boot).

For an edge host the **hardware signals are the health content** -- SMART/disk
errors accumulating, temperatures, fan RPM, resource pressure: the things that
were historically only visible through an awkward `talosctl`/SNMP CLI, which is
the whole reason to surface them. Motivate each section from a signal that
actually moves on this host (a mixin alert, a past incident, a SMART/hwmon metric
with real variance), not a dump of everything the exporter emits.

## Authoring rules (earned in #644 / fables#11)

- **Read the deployed mixin's alerts and dashboards first.** They are the
  checklist of what upstream thinks matters, and their thresholds are sourced.
  Prefer mixin thresholds over invented ones; every findings threshold should
  say where it came from.
- **Ground every focused section in a real signal -- do not LARP.** A section
  earns its place only if it targets a known or plausible-nascent failure class,
  motivated by something real: a deployed mixin alert, a historical bug/incident,
  a "true-crime" troubleshooting doc, or a metric/log that actually moves on this
  system. Speculative "if this were broken, what might we look at" content has no
  value until it is the query that actually worked when it broke -- writing it
  blind is a costume of diligence. Link an existing Grafana dashboard when that is
  the honest answer. Floor-boilerplate (pod health + a namespace-wide log tail) is
  fine as a baseline; playing pretend is not. The goal is to surface existing data
  in more focused ways, not to invent scenarios.
- **Probe the exact query you will bake in, not an approximation.** The one
  bug in the first build came from probing a cousin of the final query.
- **Silent-empty is the dominant failure mode, not errors.** PromQL/LogQL
  return `success` with empty results for typo'd metrics, wrong labels, wrong
  tenants. Treat a load-bearing empty/zero as suspicious.
- **Cross-check load-bearing facts from two independent views** (metric vs
  log, alertmanager API vs `ALERTS` series, kube API vs `kube_*` metrics) and
  warn loudly when the views disagree -- a disagreement is either a real
  finding or a broken query, and both matter.
- **Include one wide-angle, low-cleverness capture** (e.g. the last 100 raw
  log lines of anything from the namespace). It proves collection is alive and
  catches what the curated queries filtered out.
- **Do not wildcard everything.** Each notebook collects a curated set; the
  deliberate overlap between independent views is the safety net, not volume.
- **Totals + recency beat a windowed mean for episodic counters** (discards,
  errors, restarts). A mean rate over a long window collapses time and dresses a
  past spike as an ongoing condition -- the loki-usage first run showed ~790k
  discarded lines as a nonzero 7d *mean* when in fact zero had been dropped in the
  last 24h. Report `increase(...[window])` as a total alongside a recent
  (e.g. 24h) slice, and let the finding say "historical, not ongoing" when the
  recent slice is empty. The health notebook's shorter window is the natural
  cross-check on the usage notebook's longer one; when they disagree, that is the
  signal, not noise.
- **Mixin thresholds when the mixin is deployed; upstream mixin (cited) when it
  is not.** Mimir's mixin alerts run in-cluster; Loki's do not
  (`monitoring.rules.enabled: false`), so the loki notebooks source thresholds
  from the *upstream* loki-mixin and cite each one inline. Either way, a findings
  threshold that cannot name its source is invented -- fix that before shipping.
- Notebooks are code-first: brief markdown header with links out, short
  comments where the why is non-obvious. Substantial prose belongs in docs.

## Mechanics

- Run from `notebooks/` so `nb_capture` imports.
- Committed run: `jupyter nbconvert --to notebook --execute --inplace <nb>`
  (executes in place, no injected-parameters cell).
- Parameterized/scheduled: `papermill --cwd notebooks <nb> <out> -p key value`.
- Replay: `-p capture_file <capture.json>`; `-p output_dir <dir>` writes the
  raw capture and agent-stats JSON for later replay.
- **Notebooks are committed WITH output, deliberately** -- the committed
  output is the previous observation (before/after comes free) and the
  debugging lifeline when a later run breaks. Do not add nbstripout; strip at
  diff time only if diffs get painful. Re-run and commit when the notebook
  changes or the observation is worth recording, not on a timer (a scheduled
  runner writing rendered outputs to the NAS is the follow-up in #644).

## Environment facts (verified 2026-07-27; Loki facts 2026-07-29)

- Mimir: `http://mimir-gateway.mimir.svc`, header `X-Scope-OrgID: tiles`.
  Alertmanager API at `<gateway>/alertmanager/api/v2/alerts`. Configured
  limits appear in `cortex_limits_defaults` (not `_overrides`).
- Loki: `http://loki.loki.svc:3100` (SingleBinary, `gateway.enabled: false`, so
  no loki-gateway), same `X-Scope-OrgID: tiles` header (`auth_enabled: true`).
  `detected_level` is structured metadata: filter with
  `{...} | detected_level=~"error|warn"` as a pipeline stage -- in a stream
  selector it silently matches nothing.
- Loki self-metrics (`loki_*`) are scraped **into Mimir** via serviceMonitor;
  query them through `mimir-gateway.mimir.svc`, not Loki. Loki's own HTTP API is
  used only for its logs (LogQL). Loki's mixin **rules are not deployed**
  (`monitoring.rules.enabled: false`); thresholds come from the upstream
  loki-mixin (see the authoring rule above).
- Loki gotchas the notebooks bake around: (a) `loki-canary` (a DaemonSet) writes
  and reads back a known line per node -- `loki_canary_missing_entries_total` /
  `_mismatched_entries_total` are the sharpest end-to-end "logs actually flow"
  signal, their own health section. (b) Compaction recency is
  `loki_boltdb_shipper_compact_tables_operation_last_successful_run_timestamp_seconds`;
  `loki_compactor_apply_retention_*` reads 0 when retention is disabled -- a
  silent-empty trap. (c) `loki_ring_members` in SingleBinary exposes a series per
  `(name,state)` including `Unhealthy` (value 0 when healthy) -- the value is the
  count, so `{state="Unhealthy"}` is correct, but do not misread the series
  *count*. (d) Loki exports no effective per-tenant limits as metrics; the usage
  notebook reports consumption and flags limit-shaped discards, and the ceilings
  live in `loki-values.yaml` config. (e) PVCs: `loki-loki-data` (NFS RWX,
  chunks/rules) plus `storage-loki-0` (local-path, WAL) -- both must be Bound.
- The JupyterHub singleuser pod's kubectl has read-only list access for
  pods/events/services/pvc (verified in the mimir namespace); the no-LGTM
  pattern depends on this.
- Alloy (namespace `alloy`, `k8s-monitoring` chart) self-metrics (`alloy_*`,
  `prometheus_remote_storage_*`, `loki_write_*`, `otelcol_receiver_*`) are
  scraped into Mimir; that they are fresh is itself proof the Alloy->Mimir path
  works. It is deployed as several instances: `alloy-metrics` (scrape +
  remote_write), `alloy-logs` (DaemonSet), `alloy-receiver` (OTLP `:4318` for the
  edge feeds), `alloy-singleton`, and the operator. **`alloy-singleton` runs
  `mimir.rules.kubernetes` and `mimir.alerts.kubernetes`** -- i.e. it is what
  syncs `PrometheusRule` + `AlertmanagerConfig` CRs into the Mimir ruler and
  alertmanager, so if it is unhealthy, cluster alerting silently stops updating
  (found live: [#656](https://github.com/symmatree/tiles/issues/656)). Each Alloy
  instance serves `/-/ready` on `:12345` (the no-mon probe target); the metrics
  WAL is emptyDir, so the `alloy` namespace normally has no PVCs.

## Known limitations

- Kube events are TTL'd (roughly an hour): the events section is useful
  during or just after an incident, not as history.
- `kube_*` metrics retain terminated pods, so metric-side pod tables carry
  ghost rows; the kube API view disambiguates.
- The first run of a new notebook against a real system usually surfaces real
  standing issues. Distinguish "notebook broken" from "notebook correctly
  reporting brokenness" via the cross-checks before touching either.
