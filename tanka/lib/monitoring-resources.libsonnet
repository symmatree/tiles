// Shared library for loading and filtering monitoring mixins.
// Produces ConfigMaps (dashboards) and PrometheusRules (alerts, recording rules)
// from upstream mixin libsonnet packages.
//
// Multiple clusters deploy mixins to the same Grafana instance on gcp-control.
// Two mechanisms prevent collisions:
//
//   dashboardKeyPrefix  - Prepended to ConfigMap data keys AND dashboard UIDs.
//       Grafana's sidecar identifies dashboards by the UID in their JSON.
//       Without a prefix, all clusters produce identical UIDs (upstream mixins
//       derive them from the filename), and the sidecar treats them as one
//       dashboard, last-write-wins on folder placement. The prefix (typically
//       '__CLUSTER__-', replaced by Helm at deploy time) makes each cluster's
//       UIDs unique. Truncated to 8 chars of the original hash to stay within
//       Grafana's 40-character UID limit.
//
//   datasourceDefaults  - Map from dashboard template variable name to a
//       datasource UID. Sets the default datasource selection so dashboards
//       open pointing at the right Mimir/Loki instance for their cluster
//       instead of requiring the user to pick from a dropdown. Keyed by
//       variable name (not type) because a dashboard could have multiple
//       datasource variables of the same type pointing at different sources.
//
//   alertExtraSelectors  - Map from alert name to an extra label matcher, which is
//       appended inside that one alert's copy of the mixin selector (set
//       alertSelector to the same selector text the mixin was given). Use it to
//       exempt a class of targets from a single alert while leaving the rest of
//       the mixin, and the rest of the alerts on those targets, untouched --
//       alertsToDrop can only remove an alert for everyone. Because the matcher
//       goes inside the selector, a `!=` form also matches targets that lack the
//       label entirely, so only the labelled class changes. Fails the build if
//       the alert's expr does not contain alertSelector, rather than silently
//       rendering the unnarrowed rule.
//
//   tags  - List of strings injected into every dashboard's top-level "tags"
//       array. Merged (union) with any tags the upstream mixin already sets.
//       Use the __CLUSTER__ sentinel for a cluster tag that Helm replaces at
//       deploy time, plus a human-readable app name (e.g. 'kubernetes',
//       'news-serving'). This enables cross-cutting search in Grafana's
//       dashboard list by cluster or application.
//
//   deployAnnotation  - When true (default), an "ArgoCD deploys" annotation
//       query is injected into every dashboard's annotations list. It is a
//       Prometheus (Mimir) query over the already-scraped argocd_app_sync_total
//       counter, so a marker appears whenever an ArgoCD app finishes a sync and
//       metric changes line up with the deploy that caused them. This is the
//       "pull" side of the integration -- Grafana reads a metric rather than
//       ArgoCD pushing annotations, so there is no ArgoCD->Grafana dependency
//       and no API key. deployAnnotationDatasourceUid selects the datasource
//       (default 'prom', the provisioned Mimir uid on every cluster).
//
local k = import 'k.libsonnet';
local po = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';
local libutil = import 'util.libsonnet';
{
  local kConfigMap = k.core.v1.configMap,
  local defaults = {
    folder: 'Misc',
    namespace: error 'namespace',
    dashboardsToDrop: [],
    dashboardKeyPrefix: '',
    datasourceDefaults: {},
    alertGroupsToDrop: [],
    alertsToDrop: {},  // Map from group-name to list of alert names to remove.
    alertLabelOverrides: {},  // Map from alert-name to label map, e.g. { NodeDiskIOSaturation: { severity: 'info' } }
    alertSelector: '',  // The mixin's own selector text, e.g. 'job="integrations/node_exporter"'. Required by alertExtraSelectors.
    alertExtraSelectors: {},  // Map from alert-name to an extra matcher appended inside alertSelector. See file header.
    ruleGroupsToDrop: [],
    tags: [],
    dirAnnotation: 'k8s-sidecar-target-directory',
    deployAnnotation: true,  // See file header: inject an ArgoCD-deploy annotation.
    deployAnnotationDatasourceUid: 'prom',
  },
  new(mixin, overrides)::
    {
      local toK8s(name) =
        std.strReplace(std.strReplace(std.strReplace(std.asciiLower(name), ' ', '-'), '_', '-'), '.json', ''),
      mixin:: mixin,
      local config = defaults + overrides,
      assert libutil.checkFields(defaults, config),

      // See file header for why this exists.
      local narrowAlert(rule) =
        local extra = std.get(config.alertExtraSelectors, rule.alert, '');
        if extra == '' then rule
        else
          assert config.alertSelector != '' : 'alertExtraSelectors needs alertSelector set to the mixin selector text';
          local narrowed = std.strReplace(rule.expr, config.alertSelector, config.alertSelector + ', ' + extra);
          assert narrowed != rule.expr : 'alertExtraSelectors: expr of %s does not contain alertSelector %s' % [rule.alert, config.alertSelector];
          rule { expr: narrowed },

      local filterAlertGroup(group) =
        local toDrop = std.get(config.alertsToDrop, toK8s(group.name), []);
        group {
          rules: std.filterMap(
            function(rule) !std.member(toDrop, rule.alert),
            function(rule)
              local overrides = std.get(config.alertLabelOverrides, rule.alert, {});
              narrowAlert(if overrides == {} then rule else rule { labels+: overrides }),
            group.rules
          ),
        },

      // See file header for why these exist.
      local prefixUid(dashboard) =
        if config.dashboardKeyPrefix == '' || !std.objectHas(dashboard, 'uid') then dashboard
        else dashboard { uid: config.dashboardKeyPrefix + std.md5(dashboard.uid)[:8] },

      local setDatasourceDefaults(dashboard) =
        if config.datasourceDefaults == {} then dashboard
        else dashboard {
          templating+: {
            list: [
              if t.type == 'datasource' && std.objectHas(config.datasourceDefaults, t.name) then
                local uid = config.datasourceDefaults[t.name];
                t { current: { selected: true, text: uid, value: uid } }
              else t
              for t in dashboard.templating.list
            ],
          },
        },

      // See file header for why this exists.
      local setTags(dashboard) =
        if config.tags == [] then dashboard
        else
          local existing = std.sort(std.get(dashboard, 'tags', []));
          local injected = std.sort(config.tags);
          dashboard { tags: std.setUnion(existing, injected) },

      // See file header. Adds a Grafana annotation query that draws a marker on
      // every panel whenever an ArgoCD app finishes a sync, so metric changes
      // line up visually with the deploy that caused them. Pulled from the
      // already-scraped argocd_app_sync_total counter (no ArgoCD->Grafana push
      // dependency). Idempotent: skipped if a dashboard already declares one.
      local deployAnnotationQuery = {
        name: 'ArgoCD deploys',
        enable: true,
        hide: false,
        iconColor: 'rgba(255, 96, 96, 1)',
        datasource: { type: 'prometheus', uid: config.deployAnnotationDatasourceUid },
        target: {
          expr: 'changes(argocd_app_sync_total{phase="Succeeded"}[$__interval]) > 0',
          refId: 'Anno',
        },
        titleFormat: 'deploy: {{name}}',
        tagKeys: 'name,project',
        step: '60s',
      },
      local setDeployAnnotation(dashboard) =
        if !config.deployAnnotation then dashboard
        else
          local existing = std.get(dashboard, 'annotations', { list: [] });
          local existingList = std.get(existing, 'list', []);
          if std.member([std.get(a, 'name', '') for a in existingList], 'ArgoCD deploys') then dashboard
          else dashboard { annotations+: { list: existingList + [deployAnnotationQuery] } },

      local dashBlobs = mixin.grafanaDashboards,
      assert dashBlobs != null,
      dashboards: std.filterMap(
        function(name)
          !std.member(config.dashboardsToDrop, toK8s(name)),
        function(name)
          assert dashBlobs[name] != null;
          local dashContent = std.manifestJsonEx(setDeployAnnotation(setTags(prefixUid(setDatasourceDefaults(dashBlobs[name])))), indent=' ', newline='\n');
          kConfigMap.new(toK8s(name))
          + kConfigMap.metadata.withNamespace(config.namespace)
          + kConfigMap.metadata.withLabelsMixin({ grafana_dashboard: '1' })
          + kConfigMap.metadata.withAnnotationsMixin({ [config.dirAnnotation]: '/tmp/dashboards/' + config.folder })
          + kConfigMap.withData({ [config.dashboardKeyPrefix + name]: dashContent }),
        std.objectFields(dashBlobs)
      ),

      alerts: std.filterMap(
        function(group)
          !std.member(config.alertGroupsToDrop, toK8s(group.name)),
        function(group)
          {
            apiVersion: 'monitoring.coreos.com/v1',
            kind: 'PrometheusRule',
            metadata: {
              name: toK8s(group.name),
              namespace: config.namespace,
              labels: {
                'app.kubernetes.io/name': toK8s(group.name),
              },
            },
            spec: {
              groups: [
                filterAlertGroup(group),
              ],
            },
          },
        mixin.prometheusAlerts.groups
      ),

      rules: std.filterMap(
        function(group)
          !std.member(config.ruleGroupsToDrop, toK8s(group.name)),
        function(group)
          {
            apiVersion: 'monitoring.coreos.com/v1',
            kind: 'PrometheusRule',
            metadata: {
              name: toK8s(group.name),
              namespace: config.namespace,
              labels: {
                'app.kubernetes.io/name': toK8s(group.name),
              },
            },
            spec: {
              groups: [group],
            },
          },
        std.get(mixin, 'prometheusRules', { groups: [] }).groups
      ),
    },
}
