# Apprise mixin

A monitoring mixin for [Apprise](https://github.com/caronc/apprise-api) (the
`caronc/apprise` notification service): a Grafana dashboard plus alerts for
**serving** health and **delivery** health, kept as separate concerns because
Apprise can be perfectly healthy as an HTTP service while every notification is
silently dropped downstream.

There is (as of 2026-07) no Apprise mixin in the
[monitoring-mixins registry](https://monitoring.mixins.dev/); the `mixin/`
directory here is deliberately generic so it can be contributed upstream. The
tiles-specific wiring (Tanka environment, ServiceMonitor, Argo CD Application)
lives outside `mixin/`.

## Metrics it needs

Apprise exposes Prometheus metrics at `/metrics` via
[django-prometheus](https://github.com/korfuri/django-prometheus). Point a scrape
at the pod (the bundled `ServiceMonitor` in [`main.jsonnet`](main.jsonnet) does
this for the `caronc/apprise` deployment). Key series:

- `apprise_django_http_responses_total_by_status_view_method_total{view,status,method}`
  — responses by Django view and HTTP status. `view="notify"` + `status="200"`
  is a fully-delivered notification; `status="424"` means at least one target
  was not delivered.
- `apprise_django_http_requests_latency_seconds_by_view_method_bucket{view,method,le}`
  — request latency histogram.
- `process_resident_memory_bytes`, `process_cpu_seconds_total` — process resources.

The `apprise_` prefix is django-prometheus's `PROMETHEUS_METRIC_NAMESPACE`;
override `_config.metricNamespace` if your deployment differs.

## Configuration

All knobs live in [`mixin/config.libsonnet`](mixin/config.libsonnet) under
`_config`; override them the usual mixin way. The important ones:

| key | default | purpose |
| --- | --- | --- |
| `appriseSelector` | `job="apprise"` | label matcher for the Apprise target |
| `metricNamespace` | `apprise` | django-prometheus metric-name prefix |
| `notifyView` | `notify` | Django view name for the delivery endpoint |
| `servingErrorRatioThreshold` | `0.05` | 5xx ratio that trips `AppriseServingErrors` |
| `deliveryFailureFor` / `deliveryAllFailingFor` | `15m` / `30m` | delivery-alert `for` windows |

## Dashboards

- **Apprise / Overview** (`apprise-overview`): delivery success rate, notify
  outcomes by status, serving status classes, request latency quantiles,
  requests by view, and process resources.

## Alerts

Two groups, kept separate on purpose:

- **`apprise-serving`** — `AppriseDown` (target unreachable), `AppriseServingErrors`
  (sustained 5xx ratio).
- **`apprise-delivery`** — `AppriseDeliveryFailing` (any 424 on notify),
  `AppriseAllDeliveriesFailing` (notify traffic but zero successes — alerts
  reaching nobody).

## Wiring here (tiles)

[`main.jsonnet`](main.jsonnet) wraps the mixin with the shared
`monitoring-resources.libsonnet` (dashboards → ConfigMaps, alerts → PrometheusRules
that Alloy pushes to the Mimir ruler) and adds the ServiceMonitor. Deployed by
Argo CD via `charts/argocd-applications/templates/apprise-mixin-application.yaml`.
Render locally with `tk eval environments/apprise-mixin`.
