{
  _config+:: {
    nasSelector: error 'must provide selector for nas',
  },
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'nas',
        rules: [
          // {
          //   alert: 'CoreDNSDown',
          //   'for': '15m',
          //   expr: |||
          //     absent(up{%(corednsSelector)s} == 1)
          //   ||| % $._config,
          //   labels: {
          //     severity: 'critical',
          //   },
          //   annotations: {
          //     summary: 'CoreDNS has disappeared from Prometheus target discovery.',
          //     description: 'CoreDNS has disappeared from Prometheus target discovery.',
          //   },
          // },
        ],
      },
    ],
  },
}
