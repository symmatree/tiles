local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

{
  grafanaDashboards+:: {
    'apprise-overview.json':
      local cfg = $._config;
      local ds = '${' + cfg.datasourceName + '}';
      local m = cfg.metricNamespace + '_django_http_responses_total_by_status_view_method_total';
      local latBucket = cfg.metricNamespace + '_django_http_requests_latency_seconds_by_view_method_bucket';
      local notify = 'view="%s"' % cfg.notifyView;

      local q(expr, legend) =
        g.query.prometheus.new(ds, expr % cfg)
        + g.query.prometheus.withLegendFormat(legend);

      local ts(title, unit, targets, desc) =
        g.panel.timeSeries.new(title)
        + g.panel.timeSeries.panelOptions.withDescription(desc)
        + g.panel.timeSeries.standardOptions.withUnit(unit)
        + g.panel.timeSeries.options.legend.withDisplayMode('table')
        + g.panel.timeSeries.options.legend.withPlacement('bottom')
        + g.panel.timeSeries.fieldConfig.defaults.custom.withFillOpacity(10)
        + g.panel.timeSeries.queryOptions.withTargets(targets);

      local stat(title, unit, target, desc) =
        g.panel.stat.new(title)
        + g.panel.stat.panelOptions.withDescription(desc)
        + g.panel.stat.standardOptions.withUnit(unit)
        + g.panel.stat.options.withColorMode('value')
        + g.panel.stat.queryOptions.withTargets([target]);

      local pos(p, x, y, w, h) = p { gridPos: { x: x, y: y, w: w, h: h } };

      local rowAt(title, y) =
        g.panel.row.new(title) + { gridPos: { x: 0, y: y, w: 24, h: 1 } };

      // --- Overview stats ---------------------------------------------------
      local sUp = pos(stat(
        'Apprise up',
        'bool',
        q('up{%(appriseSelector)s}', 'up') + g.query.prometheus.withInstant(true),
        'Is the Apprise scrape target up.'
      ), 0, 1, 6, 4);

      local sSuccess = pos(stat(
        'Notify success rate (5m)',
        'percentunit',
        q('sum(rate(' + m + '{%(appriseSelector)s, ' + notify + ', status="200"}[5m])) / sum(rate(' + m + '{%(appriseSelector)s, ' + notify + '}[5m]))', 'success')
        + g.query.prometheus.withInstant(true),
        'Fraction of notify requests that fully delivered (HTTP 200) over 5m.'
      ), 6, 1, 6, 4);

      local sRate = pos(stat(
        'Notify requests/s (5m)',
        'reqps',
        q('sum(rate(' + m + '{%(appriseSelector)s, ' + notify + '}[5m]))', 'notify')
        + g.query.prometheus.withInstant(true),
        'Rate of notify requests Apprise is receiving.'
      ), 12, 1, 6, 4);

      local sFail = pos(stat(
        'Delivery failures/s (424, 5m)',
        'reqps',
        q('sum(rate(' + m + '{%(appriseSelector)s, ' + notify + ', status="424"}[5m]))', '424')
        + g.query.prometheus.withInstant(true),
        'Rate of notify requests where at least one target was not delivered.'
      ), 18, 1, 6, 4);

      // --- Delivery ---------------------------------------------------------
      local pOutcomes = pos(ts(
        'Notify outcomes by status',
        'reqps',
        [q('sum by (status) (rate(' + m + '{%(appriseSelector)s, ' + notify + '}[$__rate_interval]))', '{{ status }}')],
        'Notify responses per second by HTTP status. 200 = delivered to all matched targets; 424 = one or more not delivered.'
      ), 0, 6, 12, 8);

      local pRatio = pos(ts(
        'Delivery success ratio',
        'percentunit',
        [q('sum(rate(' + m + '{%(appriseSelector)s, ' + notify + ', status="200"}[$__rate_interval])) / sum(rate(' + m + '{%(appriseSelector)s, ' + notify + '}[$__rate_interval]))', 'success ratio')],
        'Share of notify requests that fully delivered.'
      ), 12, 6, 12, 8);

      // --- Serving ----------------------------------------------------------
      local pStatus = pos(ts(
        'HTTP responses by status',
        'reqps',
        [q('sum by (status) (rate(' + m + '{%(appriseSelector)s}[$__rate_interval]))', '{{ status }}')],
        'All Apprise HTTP responses per second by status (5xx = serving errors).'
      ), 0, 15, 8, 8);

      local pLatency = pos(ts(
        'Request latency',
        's',
        [
          q('histogram_quantile(0.50, sum by (le) (rate(' + latBucket + '{%(appriseSelector)s}[$__rate_interval])))', 'p50'),
          q('histogram_quantile(0.90, sum by (le) (rate(' + latBucket + '{%(appriseSelector)s}[$__rate_interval])))', 'p90'),
          q('histogram_quantile(0.99, sum by (le) (rate(' + latBucket + '{%(appriseSelector)s}[$__rate_interval])))', 'p99'),
        ],
        'Apprise request latency quantiles across all views.'
      ), 8, 15, 8, 8);

      local pByView = pos(ts(
        'Requests by view',
        'reqps',
        [q('sum by (view) (rate(' + m + '{%(appriseSelector)s}[$__rate_interval]))', '{{ view }}')],
        'Request rate by Django view (notify, health, metrics).'
      ), 16, 15, 8, 8);

      // --- Resources --------------------------------------------------------
      local pMem = pos(ts(
        'Process memory',
        'bytes',
        [q('process_resident_memory_bytes{%(appriseSelector)s}', 'rss')],
        'Resident memory of the Apprise process.'
      ), 0, 24, 12, 7);

      local pCpu = pos(ts(
        'Process CPU',
        'short',
        [q('rate(process_cpu_seconds_total{%(appriseSelector)s}[$__rate_interval])', 'cpu cores')],
        'CPU seconds per second (cores) used by the Apprise process.'
      ), 12, 24, 12, 7);

      g.dashboard.new(cfg.dashboardTitle)
      + g.dashboard.withUid(cfg.dashboardUid)
      + g.dashboard.withTags(cfg.dashboardTags)
      + g.dashboard.withTimezone(cfg.dashboardTimezone)
      + g.dashboard.withRefresh(cfg.dashboardRefresh)
      + g.dashboard.withEditable(false)
      + g.dashboard.time.withFrom(cfg.dashboardPeriod)
      + g.dashboard.time.withTo('now')
      + g.dashboard.withVariables([
        g.dashboard.variable.datasource.new(cfg.datasourceName, 'prometheus')
        + g.dashboard.variable.datasource.generalOptions.withLabel('Data source'),
      ])
      + g.dashboard.withPanels([
        rowAt('Overview', 0),
        sUp,
        sSuccess,
        sRate,
        sFail,
        rowAt('Delivery', 5),
        pOutcomes,
        pRatio,
        rowAt('Serving', 14),
        pStatus,
        pLatency,
        pByView,
        rowAt('Resources', 23),
        pMem,
        pCpu,
      ]),
  },
}
