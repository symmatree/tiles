{
  _config+:: {
    nasSelector: 'host="raconteur"',

    grafanaDashboardIDs+: {
      'nas.json': 'nas',
    },

    grafana+: {
      dashboardNamePrefix: '',
      dashboardTags: ['symm-mixin', 'nas'],

      // The default refresh time for all dashboards, default to 10s
      refresh: '10s',
    },
  },
}
