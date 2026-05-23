{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'bond-proxmox',
        rules: [
          {
            alert: 'BondProxmoxHighCoreTemperature',
            expr: |||
              avg by (instance) (
                node_hwmon_temp_celsius{
                  job="%(proxmoxNodeExporterJob)s",
                  chip="%(proxmoxHwmonCoreChip)s",
                  cluster="%(bondCluster)s",
                  %(proxmoxInstanceSelector)s
                }
              ) > %(proxmoxCoreTempThresholdCelsius)g
            ||| % $._config,
            'for': $._config.proxmoxCoreTempFor,
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'Proxmox host {{ $labels.instance }} core temperature is high',
              description: |||
                Average platform core temperature on {{ $labels.instance }} has been above %(proxmoxCoreTempThresholdCelsius)g C for %(proxmoxCoreTempFor)s (current value {{ printf "%%.1f" $value }} C).
              ||| % $._config,
            },
          },
        ],
      },
    ],
  },
}
