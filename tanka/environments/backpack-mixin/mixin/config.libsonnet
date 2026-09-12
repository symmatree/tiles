{
  _config+:: {
    // --- target selection ---------------------------------------------------
    // Label matcher identifying the backpack scrape. The Probe that drives this
    // (mavproxy environment) sets `jobName: backpack`, so this default works
    // out-of-the-box; override it if you probe the endpoint under another job.
    backpackSelector: 'job="backpack"',

    // --- dashboard ----------------------------------------------------------
    dashboardTags: ['backpack', 'drone'],
    dashboardTitle: 'Backpack / Link health',
    dashboardUid: 'backpack-link-health',
    dashboardPeriod: 'now-24h',
    dashboardTimezone: 'utc',
    dashboardRefresh: '1m',
    // Window for the at-a-glance availability and reconnect stats.
    summaryWindow: '24h',
    // Name of the datasource template variable; the deploy-time wrapper can set
    // its default via `datasourceDefaults` so the dashboard opens on the right
    // Prometheus/Mimir without a manual pick.
    datasourceName: 'datasource',
  },
}
