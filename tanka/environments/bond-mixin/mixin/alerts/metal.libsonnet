{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'bond-metal',
        rules: [
          {
            // Bare-metal Talos workers (lancer=AMD/k10temp, acebase=Intel/coretemp) report
            // hwmon temps into Mimir since #580/#685. The CPU chip label is a hashed PCI path
            // (k10temp) or platform_coretemp_0 (coretemp), so we select the CPU sensor by
            // joining on node_hwmon_chip_names.chip_name -- which also auto-scopes to nodes
            // that actually have CPU hwmon (VMs emit none), so future metal nodes are covered
            // without listing instances. max (not avg) to catch the hottest core.
            alert: 'BondMetalHighCpuTemperature',
            expr: |||
              max by (instance) (
                node_hwmon_temp_celsius{
                  job="%(metalNodeExporterJob)s",
                  cluster="%(metalCluster)s",
                }
                * on (instance, chip) group_left (chip_name)
                node_hwmon_chip_names{chip_name=~"%(metalCpuChipNames)s"}
              ) > %(metalCpuTempThresholdCelsius)g
            ||| % $._config,
            'for': $._config.metalCpuTempFor,
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'Bare-metal node {{ $labels.instance }} CPU temperature is high',
              description: |||
                Hottest CPU sensor (k10temp/coretemp) on {{ $labels.instance }} has been above %(metalCpuTempThresholdCelsius)g C for %(metalCpuTempFor)s (current value {{ printf "%%.1f" $value }} C).
              ||| % $._config,
            },
          },
        ],
      },
    ],
  },
}
