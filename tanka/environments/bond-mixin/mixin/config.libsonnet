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

    // Bare-metal Talos workers (cluster="tiles"): CPU temp via chip_name join, so both
    // Intel (coretemp) and AMD (k10temp) match without hardcoding node names or hashed chips.
    metalNodeExporterJob: 'integrations/node_exporter',
    metalCluster: 'tiles',
    metalCpuChipNames: 'k10temp|coretemp',
    metalCpuTempThresholdCelsius: 90,
    metalCpuTempFor: '10m',

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
  },
}
