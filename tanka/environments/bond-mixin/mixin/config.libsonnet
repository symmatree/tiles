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
  },
}
