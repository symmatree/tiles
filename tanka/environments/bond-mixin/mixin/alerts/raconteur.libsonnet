{
  local cfg = $._config,
  local snmpSel = 'cluster="%(bondCluster)s", job="%(raconteurSnmpJob)s"' % cfg,
  local hostSel = 'cluster="%(bondCluster)s", instance="%(raconteurInstance)s"' % cfg,
  local diskTempWithType =
    |||
      diskTemperature{%(snmp)s}
      * on(diskIndex) group_left(diskType)
      diskType{%(snmp)s}
    ||| % (cfg { snmp: snmpSel }),
  local c = cfg {
    snmp: snmpSel,
    host: hostSel,
    diskTempWithType: diskTempWithType,
  },

  prometheusAlerts+:: {
    groups+: [
      {
        name: 'bond-raconteur',
        rules: [
          {
            alert: 'BondRaconteurSystemFanFailed',
            expr: 'systemFanStatus{%(snmp)s} == %(raconteurSnmpFanFailedValue)g' % c,
            'for': c.raconteurFanFailedFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur system fan failed',
              description: 'Synology systemFanStatus is 2 (failed).',
            },
          },
          {
            alert: 'BondRaconteurCpuFanFailed',
            expr: 'cpuFanStatus{%(snmp)s} == %(raconteurSnmpFanFailedValue)g' % c,
            'for': c.raconteurFanFailedFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur CPU fan failed',
              description: 'Synology cpuFanStatus is 2 (failed).',
            },
          },
          {
            alert: 'BondRaconteurCpuTemperatureHigh',
            expr: |||
              max without (sensor) (
                node_hwmon_temp_celsius{
                  %(host)s,
                  job="%(raconteurNodeExporterJob)s",
                  chip="%(raconteurCpuChip)s"
                }
              ) > %(raconteurCpuTempCelsius)g
            ||| % c,
            'for': c.raconteurCpuTempFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur CPU temperature high',
              description: 'Max coretemp above %(raconteurCpuTempCelsius)g C for %(raconteurCpuTempFor)s (now {{ printf "%%.1f" $value }} C).' % c,
            },
          },
          {
            alert: 'BondRaconteurSataDiskTemperatureHigh',
            expr: |||
              %(diskTempWithType)s{diskType="%(raconteurDiskTypeSata)s"}
              > %(raconteurDiskSataTempCelsius)g
            ||| % c,
            'for': c.raconteurDiskSataTempFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur SATA disk {{ $labels.diskIndex }} hot',
              description: 'Disk {{ $labels.diskIndex }} above %(raconteurDiskSataTempCelsius)g C for %(raconteurDiskSataTempFor)s.' % c,
            },
          },
          {
            alert: 'BondRaconteurSsdDiskTemperatureHigh',
            expr: |||
              %(diskTempWithType)s{diskType="%(raconteurDiskTypeSsd)s"}
              > %(raconteurDiskSsdTempCelsius)g
            ||| % c,
            'for': c.raconteurDiskSsdTempFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur SSD disk {{ $labels.diskIndex }} hot',
              description: 'Disk {{ $labels.diskIndex }} above %(raconteurDiskSsdTempCelsius)g C for %(raconteurDiskSsdTempFor)s.' % c,
            },
          },
        ],
      },
    ],
  },
}
