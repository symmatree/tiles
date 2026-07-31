{
  local cfg = $._config,
  local snmpSel = 'cluster="%(bondCluster)s", job="%(raconteurSnmpJob)s"' % cfg,
  local hostSel = 'cluster="%(bondCluster)s", instance="%(raconteurInstance)s"' % cfg,
  local diskTempSata =
    'diskTemperature{%(snmp)s} * on(diskIndex) group_left(diskType) diskType{%(snmp)s, diskType="%(raconteurDiskTypeSata)s"}'
    % (cfg { snmp: snmpSel }),
  local diskTempSsd =
    'diskTemperature{%(snmp)s} * on(diskIndex) group_left(diskType) diskType{%(snmp)s, diskType="%(raconteurDiskTypeSsd)s"}'
    % (cfg { snmp: snmpSel }),
  local c = cfg {
    snmp: snmpSel,
    host: hostSel,
    diskTempSata: diskTempSata,
    diskTempSsd: diskTempSsd,
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
            expr: '%(diskTempSata)s > %(raconteurDiskSataTempCelsius)g' % c,
            'for': c.raconteurDiskSataTempFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur SATA disk {{ $labels.diskIndex }} hot',
              description: 'Disk {{ $labels.diskIndex }} above %(raconteurDiskSataTempCelsius)g C for %(raconteurDiskSataTempFor)s.' % c,
            },
          },
          {
            alert: 'BondRaconteurSsdDiskTemperatureHigh',
            expr: '%(diskTempSsd)s > %(raconteurDiskSsdTempCelsius)g' % c,
            'for': c.raconteurDiskSsdTempFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur SSD disk {{ $labels.diskIndex }} hot',
              description: 'Disk {{ $labels.diskIndex }} above %(raconteurDiskSsdTempCelsius)g C for %(raconteurDiskSsdTempFor)s.' % c,
            },
          },
          {
            alert: 'BondRaconteurDiskUnhealthy',
            expr: 'diskHealthStatus{%(snmp)s} > 1' % c,
            'for': c.raconteurDiskHealthFor,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Raconteur disk {{ $labels.diskIndex }} health not Normal',
              description: 'Synology diskHealthStatus is {{ $value }} (1=Normal, 2=Warning, 3=Critical, 4=Failing). DSM alerts on this natively; this is the belt-and-suspenders copy.',
            },
          },
          {
            alert: 'BondRaconteurVolumeDegraded',
            expr: 'raidStatus{%(snmp)s} >= 11 and raidStatus{%(snmp)s} <= 12' % c,
            'for': c.raconteurVolumeBadFor,
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Raconteur volume/pool {{ $labels.raidIndex }} degraded or crashed',
              description: 'Synology raidStatus is {{ $value }} (11=Degrade, 12=Crashed). The monthly scrub/resilver shows as other states and is intentionally not alerted.',
            },
          },
        ],
      },
    ],
  },
}
