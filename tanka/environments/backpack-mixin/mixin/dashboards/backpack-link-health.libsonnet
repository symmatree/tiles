local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

{
  grafanaDashboards+:: {
    'backpack-link-health.json':
      local cfg = $._config;
      local ds = '${' + cfg.datasourceName + '}';

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

      // --- Overview ---------------------------------------------------------
      local sUp = pos(stat(
        'Backpack reachable',
        'bool',
        q('up{%(backpackSelector)s}', 'up') + g.query.prometheus.withInstant(true),
        'Is the /mavlink endpoint answering right now. 0 is the resting state: the backpack is only on WiFi when the radio is powered and Telem mode = WiFi.'
      ), 0, 1, 6, 4);

      local sAvail = pos(stat(
        'Reachable share (%(summaryWindow)s)' % cfg,
        'percentunit',
        q('avg_over_time(up{%(backpackSelector)s}[%(summaryWindow)s])', 'reachable')
        + g.query.prometheus.withInstant(true),
        'Fraction of scrapes in the window that reached the backpack. Compare across placement/antenna changes -- but read it against how long the radio was actually on.'
      ), 6, 1, 6, 4);

      local sRssi = pos(stat(
        'RSSI',
        'dBm',
        q('backpack_wifi_rssi_dbm{%(backpackSelector)s}', 'rssi')
        + g.query.prometheus.withInstant(true),
        'Latest backpack-to-AP RSSI. Around -75 dBm and worse is a marginal link.'
      ), 12, 1, 6, 4);

      local sReconnects = pos(stat(
        'Reconnects (%(summaryWindow)s)' % cfg,
        'short',
        q('increase(backpack_wifi_reconnects_total{%(backpackSelector)s}[%(summaryWindow)s])', 'reconnects')
        + g.query.prometheus.withInstant(true),
        'WiFi drops the backpack rode out by reconnecting. Rising while still reachable is the reconnect patch working; on stock firmware each of these stranded it on its own AP until a power-cycle.'
      ), 18, 1, 6, 4);

      // --- WiFi link --------------------------------------------------------
      local pUp = pos(ts(
        'Endpoint reachable',
        'bool',
        [q('up{%(backpackSelector)s}', 'up')],
        'Scrape success over time -- the backpack-on-the-network availability series. Gaps are the backpack off, off-network, or associating.'
      ), 0, 6, 12, 8);

      local pRssi = pos(ts(
        'RSSI',
        'dBm',
        [q('backpack_wifi_rssi_dbm{%(backpackSelector)s}', 'rssi')],
        'Backpack-to-AP signal strength as reported by the esp8285.'
      ), 12, 6, 12, 8);

      local pReconnects = pos(ts(
        'Reconnects (cumulative)',
        'short',
        [q('backpack_wifi_reconnects_total{%(backpackSelector)s}', 'reconnects')],
        'Reconnect counter since backpack boot. Steps up on each WL_CONNECTION_LOST that the patched firmware recovered from; drops back to 0 when the backpack reboots.'
      ), 0, 14, 12, 8);

      local pUptime = pos(ts(
        'Backpack uptime',
        'ms',
        [q('backpack_uptime_milliseconds{%(backpackSelector)s}', 'uptime')],
        'millis() since boot. A reset to near zero is a backpack reboot (power-cycle or crash) -- which also clears the GCS latch and the reconnect counter.'
      ), 12, 14, 12, 8);

      // --- MAVLink bridge ---------------------------------------------------
      local pPackets = pos(ts(
        'Bridged packets',
        'pps',
        [
          q('rate(backpack_mavlink_packets_up_total{%(backpackSelector)s}[$__rate_interval])', 'up (ground -> air)'),
          q('rate(backpack_mavlink_packets_down_total{%(backpackSelector)s}[$__rate_interval])', 'down (air -> ground)'),
        ],
        'MAVLink packets per second across the bridge. Uplink carries the RTCM corrections; downlink is zero whenever the drone is off.'
      ), 0, 22, 8, 8);

      local pLoss = pos(ts(
        'Drops and overflows',
        'pps',
        [
          q('rate(backpack_mavlink_drops_down_total{%(backpackSelector)s}[$__rate_interval])', 'drops_down'),
          q('rate(backpack_mavlink_overflows_down_total{%(backpackSelector)s}[$__rate_interval])', 'overflows_down'),
        ],
        'overflows_down is genuine link-capacity pressure. drops_down is a counting artifact (one global MAVLink sequence across several interleaved sources), so treat it as suspect rather than as loss.'
      ), 8, 22, 8, 8);

      local pLatency = pos(ts(
        'Endpoint response time',
        's',
        [q('scrape_duration_seconds{%(backpackSelector)s}', 'scrape duration')],
        'How long the whole scrape took, dominated by the backpack answering /mavlink. A climbing trend on a marginal link is the esp8285 struggling.'
      ), 16, 22, 8, 8);

      // --- Identity ---------------------------------------------------------
      local tIdentity = pos(
        g.panel.table.new('Association and GCS')
        + g.panel.table.panelOptions.withDescription('Who the backpack is associated with (ssid/bssid) and which GCS it has latched onto. gcs should be acebase (10.0.99.14, mavproxy); "IP UNSET" means it has not latched yet.')
        + g.panel.table.queryOptions.withTargets([
          q('backpack_mavlink_enabled{%(backpackSelector)s}', 'enabled')
          + g.query.prometheus.withInstant(true)
          + g.query.prometheus.withFormat('table'),
          q('backpack_wifi_link_info{%(backpackSelector)s}', 'link')
          + g.query.prometheus.withInstant(true)
          + g.query.prometheus.withFormat('table'),
          q('backpack_mavlink_gcs_info{%(backpackSelector)s}', 'gcs')
          + g.query.prometheus.withInstant(true)
          + g.query.prometheus.withFormat('table'),
        ]),
        0, 30, 24, 6
      );

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
        sAvail,
        sRssi,
        sReconnects,
        rowAt('WiFi link', 5),
        pUp,
        pRssi,
        pReconnects,
        pUptime,
        rowAt('MAVLink bridge', 21),
        pPackets,
        pLoss,
        pLatency,
        rowAt('Identity', 29),
        tIdentity,
      ]),
  },
}
