{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'bond-feeds',
        rules: [
          {
            // A bond source (job, instance) that reported `up` at some point in the lookback
            // window but has no current sample. The window is the list of expected sources, so
            // none are named here. A source removed on purpose fires until it ages out of the
            // window.
            alert: 'BondFeedAbsent',
            expr: |||
              max by (job, instance) (max_over_time(up{cluster="%(bondCluster)s"}[%(bondFeedLookback)s]))
              unless
              max by (job, instance) (up{cluster="%(bondCluster)s"})
            ||| % $._config,
            'for': $._config.bondFeedAbsentFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Edge feed {{ $labels.job }} / {{ $labels.instance }} has stopped reporting',
              description: 'No `up` sample from {{ $labels.job }} / {{ $labels.instance }} (cluster="%(bondCluster)s") for %(bondFeedAbsentFor)s; it reported within the last %(bondFeedLookback)s.' % $._config,
            },
          },
        ],
      },
    ],
  },
}
