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
//
// Deployed unmodified, including one panel that reads "No data" here. "Firing Alerts" queries
// grafana_alerting_result_total, a metric from Grafana's legacy alerting engine that 12.3.1 no
// longer emits. Rewriting it to the unified-alerting equivalent (grafana_alerting_alerts) is
// possible but pointless: this deployment defines no Grafana-native alert rules -- all alerting
// is mixin -> Mimir ruler -- so a working panel would read a permanent zero. Upstream mixins
// carry assumptions about deployments that are not this one; where the result is a dead panel
// rather than a wrong number, leaving it alone is cheaper than carrying a patch for it.
local grafanaMixin = import 'mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  grafanaMixin,
  {
    folder: 'Grafana',
    namespace: 'grafana',
    tags: ['grafana'],
  },
)
