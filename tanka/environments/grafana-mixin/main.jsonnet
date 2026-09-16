// Grafana's own mixin: one overview dashboard, one alert, and the recording rule that alert
// depends on. Small, but it is the upstream view of what matters about a Grafana, and it costs
// nothing to run -- Grafana's self-metrics have been scraped into Mimir since #752.
//
// Why mixin/ is vendored instead of a jsonnetfile dependency: the mixin lives inside
// grafana/grafana, a 1.9 GB repository -- twelve times the largest dependency already in
// jsonnetfile.json (grafana/alloy, 159 MB) and 160x the other mixins. The Tanka CMP runs
// `jb install` in the ArgoCD repo-server on every lockfile change (charts/argocd/templates/
// tanka.yaml), so adding it would drag that clone through the repo-server to obtain 32 KB of
// jsonnet. Vendored with provenance in mixin/UPSTREAM.md instead. See docs/monitoring-mixins.md.
local grafanaMixin = import 'mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

// Upstream's "Firing Alerts" panel queries grafana_alerting_result_total, a metric from
// Grafana's LEGACY alerting engine. Grafana 12.3.1 (deployed here) emits 82 grafana_alerting_*
// series and that is not among them, so the panel would read "No data" forever.
// grafana_alerting_alerts is the unified-alerting equivalent: same gauge shape, same `state`
// label. Patched here rather than in mixin/ so the vendored copy stays byte-identical to
// upstream and diffing it against a newer release stays meaningful.
local legacyAlertingExpr = 'grafana_alerting_result_total{job=~"$job", instance=~"$instance", state="alerting"}';
local unifiedAlertingExpr = 'grafana_alerting_alerts{job=~"$job", instance=~"$instance", state="alerting"}';

local overview = grafanaMixin.grafanaDashboards['grafana-overview.json'];

// Fail the build if upstream changes that panel, rather than silently patching nothing: a
// no-op rewrite is exactly the kind of dead config that survives for years unnoticed.
local legacyHits = std.length([
  t
  for p in overview.panels
  for t in std.get(p, 'targets', [])
  if std.get(t, 'expr', '') == legacyAlertingExpr
]);
assert legacyHits == 1 : |||
  Expected exactly one panel target using the legacy alerting metric, found %d.
  Upstream grafana-mixin has changed: re-check whether this patch is still needed
  (see mixin/UPSTREAM.md for the pinned commit and the update procedure).
||| % legacyHits;

local patchTarget(t) =
  if std.get(t, 'expr', '') == legacyAlertingExpr then t { expr: unifiedAlertingExpr } else t;

local patchPanel(p) =
  if !std.objectHas(p, 'targets') then p
  else p { targets: [patchTarget(t) for t in p.targets] };

libMonResources.new(
  grafanaMixin {
    grafanaDashboards+:: {
      'grafana-overview.json': overview {
        panels: [patchPanel(p) for p in overview.panels],
      },
    },
  },
  {
    folder: 'Grafana',
    namespace: 'grafana',
    tags: ['grafana'],
  },
)
