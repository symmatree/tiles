# Mimir (metrics backend)

Prometheus-compatible metrics are stored in **Grafana Mimir** (mimir-distributed chart,
deployed by Argo CD via [`charts/argocd-applications/templates/mimir-application.yaml`](../charts/argocd-applications/templates/mimir-application.yaml)).
Static values are in [`charts/argocd-applications/values/mimir-values.yaml`](../charts/argocd-applications/values/mimir-values.yaml);
per-cluster overrides in `mimir-<cluster>-values.yaml`.

## Tenancy

Mimir runs with **`multitenancy_enabled: true`** and **`tenant_federation.enabled: true`**.
Tenant is selected by the **`X-Scope-OrgID`** header.

- The cluster's **Alloy** (k8s-monitoring) stack writes all metrics with
  `tenantId = <cluster_name>` — so on prod everything lands in tenant **`tiles`**
  (see [`alloy-application.yaml`](../charts/argocd-applications/templates/alloy-application.yaml)).
- The Grafana **Mimir** datasource (`uid: prom`) queries with the same
  `X-Scope-OrgID: <cluster_name>` header, i.e. **`tiles`**.
- Edge sources (Synology, Proxmox) ship OTLP with `X-Scope-OrgID: tiles` too; their
  data is distinguished by the **`cluster="bond"`** label, not by tenant. See
  [`synology-monitoring.md`](synology-monitoring.md) and [`proxmox-monitoring.md`](proxmox-monitoring.md).

There is currently **one active tenant per cluster** (`tiles`, `tiles-test`). Edge
data is not yet isolated into its own tenant; that's a known follow-up (edge
cardinality shares the k8s tenant's series budget).

## Limits

Set under `mimir.structuredConfig.limits`:

- **`max_global_series_per_user: 500000`** — raised from the 150k default (#311) because
  prod was hitting the per-tenant active-series cap and refusing edge (Synology) metrics.
- **`cardinality_analysis_enabled: true`** — enables the on-demand cardinality API
  (see below). Default is `false`.
- `max_fetched_chunks_per_query`, `ruler_max_rules_per_rule_group`.

## Self-monitoring

Mimir components expose their own `/metrics` (the `cortex_*` family). They are scraped
only if a **ServiceMonitor** exists for them — the Alloy k8s-monitoring stack discovers
ServiceMonitors cluster-wide and writes them into the `tiles` tenant (this is how
`argocd_*`, `cilium_*`, `loki_*`, etc. arrive).

`metaMonitoring.serviceMonitor.enabled: true` in `mimir-values.yaml` makes the chart
emit a ServiceMonitor per component. `clusterLabel: null` keeps Mimir from stamping its
own `cluster` label (which would otherwise default to the release name `mimir`) so the
Alloy pipeline's `cluster` label stays authoritative.

> History: before this was enabled, the `mimir` namespace had **no** ServiceMonitors, so
> `cortex_*` metrics were exposed but scraped by nothing — cardinality and load were
> unanswerable. See #556.

## Answering cardinality & load questions

Run these in **Grafana Explore** on the **Mimir** datasource (tenant `tiles`).

### Series count vs. the per-tenant cap

```promql
# in-memory series across ingesters (global)
sum(cortex_ingester_memory_series)
```

```promql
# active series for a tenant, vs the 500k max_global_series_per_user cap
sum(cortex_ingester_active_series{user="tiles"})
```

### Ingest / query load

```promql
# samples ingested per second
sum(rate(cortex_distributor_received_samples_total[5m]))
```

```promql
# query rate by route
sum by (route) (rate(cortex_request_duration_seconds_count{route=~"prometheus.*"}[5m]))
```

### What's driving cardinality

With `cardinality_analysis_enabled: true`, use Grafana Explore's **"Analyse cardinality"**
on the Mimir datasource, or hit the API directly (send the `X-Scope-OrgID` header):

```
GET /prometheus/api/v1/cardinality/label_names
GET /prometheus/api/v1/cardinality/label_values?label_names[]=<label>
GET /prometheus/api/v1/cardinality/active_series?selector=<matcher>
```

```bash
# via the gateway, from inside the cluster
curl -H 'X-Scope-OrgID: tiles' \
  'http://mimir-gateway.mimir.svc/prometheus/api/v1/cardinality/label_names?limit=20'
```

For a first cut without the API, break series down by metric name:

```promql
topk(20, count by (__name__) ({cluster="bond"}))
```

## Storage

Blocks, ruler, and alertmanager state live on the shared **NFS** volume mounted at
`/mnt/mimir-nfs` (`filesystem` backend). See [`nfs-storage-architecture.md`](nfs-storage-architecture.md).

## Related

- [`monitoring-mixins.md`](monitoring-mixins.md) — recording/alerting rules
- [`synology-monitoring.md`](synology-monitoring.md), [`proxmox-monitoring.md`](proxmox-monitoring.md) — edge (`cluster="bond"`) sources
- Issues #306 (edge metrics not landing — fixed), #311 (limit raise), #556 (self-monitoring)
