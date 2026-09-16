# Vendored: grafana/grafana `grafana-mixin`

Verbatim copy of the upstream mixin. **Do not edit these files** -- local deviations go in
[`../main.jsonnet`](../main.jsonnet) so a diff against a newer upstream stays meaningful.

| | |
|---|---|
| Source | <https://github.com/grafana/grafana/tree/main/grafana-mixin> |
| Pinned commit | `a6ce3be0abeecdc296020b46437ecf5ac718964a` |
| Last upstream change to `grafana-mixin/` | `9646a06a91c5`, 2025-08-25 |
| Vendored | 2026-09-16 |
| Size here | 32 KB (5 files) |

## Why vendored rather than a jsonnetfile dependency

Every other mixin in this repo comes through `jb`. This one does not, because the mixin lives
inside `grafana/grafana` -- a **1.9 GB** repository, 12x the largest dependency already in
`jsonnetfile.json` (`grafana/alloy`, 159 MB) and ~160x the other mixins. The Tanka CMP runs
`jb install` inside the ArgoCD repo-server on every lockfile change
([`charts/argocd/templates/tanka.yaml`](../../../../charts/argocd/templates/tanka.yaml)), and the
repo-server has no memory limit and has OOM-crashlooped on Tanka work before. Dragging a 1.9 GB
clone through it to obtain 32 KB of jsonnet is a bad trade.

## What it contains

- `dashboards/grafana-overview.json` -- 5 panels: firing alerts, dashboard count, build info,
  RPS by status code, request latency (p99/p50/avg).
- `alerts/alerts.libsonnet` -- one alert, `GrafanaRequestsFailing` (>50% 5xx on a handler for
  5m, excluding the datasource-proxy and query handlers).
- `rules/rules.libsonnet` -- the recording rule that alert reads,
  `namespace_job_handler_statuscode:grafana_http_request_duration_seconds_count:rate5m`.
  It ships **with** the mixin; `mixin.libsonnet` imports all three files, and
  `monitoring-resources.libsonnet` already turns `prometheusRules` into a PrometheusRule.

## Updating

1. Re-fetch the five files from a newer commit and update the table above.
2. Run `tk eval environments/grafana-mixin`. `main.jsonnet` asserts that exactly one panel
   target still uses the legacy `grafana_alerting_result_total` metric; if upstream has fixed
   that panel the build fails, which is the signal to delete the local patch.
3. Re-run [`notebooks/grafana-health.ipynb`](../../../../notebooks/grafana-health.ipynb) --
   it reads the deployed alert's threshold, so a changed threshold shows up there.
