# Mimir

## Interesting points

This is pretty stock, but a few decisions:

* Tenanted, though so far using a single tenant; expecting to have external resources pushing at some point.
* Uses Mimir AlertManager for metrics-based alerting, not just Grafana. This is based on a comment from one of
  the Grafana devs on a bug stating that they would absolutely recommend this setup and only using Grafana
  alerting for combining multiple data sources or other fanciness that only it can do.
* Does not do its own scraping, expects to have metrics pushed to it from Alloy.
* Gets Rules pushed to it by Alloy; evaluates and sends alerts.
* Notifications go through a sidecar pod that accepts a webhook call and formats it to push to AppRise.

## Configuration

External chart (`mimir-distributed` from Grafana). Values are split across:

| Location | Role |
|----------|------|
| [`values/mimir-values.yaml`](../values/mimir-values.yaml) | Static chart values (structured config, caches, sidecar, affinity, etc.) |
| [`values/mimir-tiles-test-values.yaml`](../values/mimir-tiles-test-values.yaml) | Resource requests/limits for `tiles-test` |
| [`values/mimir-tiles-values.yaml`](../values/mimir-tiles-values.yaml) | Resource requests/limits for `tiles` (prod; same as legacy monolith until tuned) |
| [`mimir-application.yaml`](mimir-application.yaml) `valuesObject` | Cluster-templated keys only (gateway ingress, `extraObjects`, datasource org headers) |

The Application uses [multi-source](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/#helm-value-files-from-external-git-repository): Grafana chart + tiles git `ref: values` so `valueFiles` can use `$values/charts/argocd-applications/values/...`. Merge order: chart defaults &lt; `valueFiles` (base then `mimir-<cluster_name>-values.yaml`) &lt; `valuesObject`. Do not split `extraObjects` across `valueFiles` and `valuesObject`: Helm replaces whole arrays; `valuesObject` wins.

**Other apps with `valueFiles` + `valuesObject`:** `ingress` / nested maps (Grafana, Mimir `gateway`, Cilium `hubble.ui.ingress`, Argo CD `argo-cd`) merge by key. `plugins`, `sidecar`, and other list-valued keys should live in only one layer unless you intend the later layer to replace the list entirely.

* **Tenant Limits**: `ruler_max_rules_per_rule_group` is 100 in `mimir-values.yaml` (increased from default 20 for workload headroom).
