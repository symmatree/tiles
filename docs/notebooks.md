# Analysis notebooks -- pattern and authoring guide

Standing analysis of deployed software as Jupyter notebooks: deterministic data
collection plus a rendered judgment surface for both humans and agents. The LLM
does the thinking; the notebook does the data collection -- instead of an agent
re-deriving "check mimir health" through dozens of ad-hoc tool calls each
session, it reads one artifact whose rote layer is mechanized and re-runnable.
Tracking issue: [#644](https://github.com/symmatree/tiles/issues/644). Deeper
design rationale lives in the facts KB (`notebook-analysis/design-intent.md`);
the first exemplar of the pattern is `flight-analysis.ipynb` in the fables repo.

Current notebooks: [`notebooks/`](../notebooks/) -- `mimir-health.ipynb`,
`mimir-usage.ipynb`, `mimir-nolgtm.ipynb`, sharing
[`nb_capture.py`](../notebooks/nb_capture.py).

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
  smoke check, never as an instrument.

## Authoring rules (earned in #644 / fables#11)

- **Read the deployed mixin's alerts and dashboards first.** They are the
  checklist of what upstream thinks matters, and their thresholds are sourced.
  Prefer mixin thresholds over invented ones; every findings threshold should
  say where it came from.
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

## Environment facts (verified 2026-07-27)

- Mimir: `http://mimir-gateway.mimir.svc`, header `X-Scope-OrgID: tiles`.
  Alertmanager API at `<gateway>/alertmanager/api/v2/alerts`. Configured
  limits appear in `cortex_limits_defaults` (not `_overrides`).
- Loki: `http://loki.loki.svc:3100` (not loki-gateway), same tenant header.
  `detected_level` is structured metadata: filter with
  `{...} | detected_level=~"error|warn"` as a pipeline stage -- in a stream
  selector it silently matches nothing.
- The JupyterHub singleuser pod's kubectl has read-only list access for
  pods/events/services/pvc (verified in the mimir namespace); the no-LGTM
  pattern depends on this.

## Known limitations

- Kube events are TTL'd (roughly an hour): the events section is useful
  during or just after an incident, not as history.
- `kube_*` metrics retain terminated pods, so metric-side pod tables carry
  ghost rows; the kube API view disambiguates.
- The first run of a new notebook against a real system usually surfaces real
  standing issues. Distinguish "notebook broken" from "notebook correctly
  reporting brokenness" via the cross-checks before touching either.
