// Synology SNMP exposes OctetString fields (diskType, diskModel, ...) as hex-encoded ASCII on the metric label.
local snmpHexLabel(str) =
  '0x' + std.foldl(
    function(acc, c) acc + std.format('%02x', std.codepoint(c)),
    std.stringChars(str),
    '',
  );

{
  _config+:: {
    bondCluster: 'bond',

    proxmoxNodeExporterJob: 'integrations/node_exporter',
    proxmoxHwmonCoreChip: 'platform_coretemp_0',
    proxmoxCoreTempThresholdCelsius: 90,
    proxmoxCoreTempFor: '10m',
    proxmoxInstanceSelector: 'instance=~"nuc-g.*"',
    // Dashboard-only (no alert). Only the g3p NUCs expose an NVMe hwmon; g2p report none.
    proxmoxStorageChipNames: 'nvme',

    // Bare-metal Talos workers (cluster="tiles"): CPU temp via chip_name join, so both
    // Intel (coretemp) and AMD (k10temp) match without hardcoding node names or hashed chips.
    metalNodeExporterJob: 'integrations/node_exporter',
    metalCluster: 'tiles',
    metalCpuChipNames: 'k10temp|coretemp',
    metalCpuTempThresholdCelsius: 90,
    metalCpuTempFor: '10m',
    // iGPU: only AMD APUs expose a GPU hwmon (amdgpu); no temp_crit is reported, so fixed warn
    // set above the CPU's (APU GPU runs hotter under load, throttles ~95-100 C).
    metalGpuChipNames: 'amdgpu',
    metalGpuTempThresholdCelsius: 95,
    metalGpuTempFor: '10m',
    // Storage sensors, dashboard-only (no alert): lancer NVMe, acebase SATA SSD via drivetemp.
    metalStorageChipNames: 'nvme|drivetemp',

    raconteurInstance: 'raconteur',
    raconteurSnmpJob: 'integrations/snmp/raconteur',
    raconteurNodeExporterJob: 'integrations/node_exporter',
    raconteurCpuChip: 'platform_coretemp_0',
    raconteurDiskTypeSata: snmpHexLabel('SATA'),
    raconteurDiskTypeSsd: snmpHexLabel('SSD'),

    raconteurCpuTempCelsius: 80,
    raconteurCpuTempFor: '10m',
    raconteurDiskSataTempCelsius: 55,
    raconteurDiskSataTempFor: '15m',
    raconteurDiskSsdTempCelsius: 65,
    raconteurDiskSsdTempFor: '15m',
    raconteurFanFailedFor: '2m',
    raconteurSnmpFanFailedValue: 2,
    // Belt-and-suspenders for disk/array failure (DSM alerts on this natively too).
    // Deliberately does NOT fire on the monthly scrub/resilver: those show as other
    // raidStatus values (7 syncing, 8 parity-check, 13 scrubbing), not 11/12.
    raconteurDiskHealthFor: '15m',
    raconteurVolumeBadFor: '5m',

    // --- dashboard ----------------------------------------------------------
    dashboardTags: ['bond', 'temperature'],
    dashboardTitle: 'Bond / Temperatures',
    dashboardUid: 'bond-temperature',
    dashboardPeriod: 'now-24h',
    dashboardTimezone: 'utc',
    dashboardRefresh: '1m',
    // Name of the datasource template variable; the deploy-time wrapper can set its default
    // via `datasourceDefaults` so the dashboard opens on the right Mimir without a manual pick.
    datasourceName: 'datasource',

    // Some hardware reports its own shutdown limit in node_hwmon_temp_crit_celsius, which is a
    // far better reference line than a fixed threshold -- but drivers also emit sentinels for
    // "no limit set" (acebase's drivetemp and raconteur's i2c chip both report 127; the NVMe
    // composite sensors report 65261.85 in the sibling _max metric). Anything outside this band
    // is a sentinel, not a limit, and is dropped so the board shows crit only where it is real.
    critSaneMinCelsius: 40,
    critSaneMaxCelsius: 120,

    // Passive-throttle cooling devices. Fan and PCIe_Port_Link_Speed entries are step devices
    // on an unrelated scale, so they are excluded.
    coolingDeviceTypes: 'Processor|intel_powerclamp',
  },
}
