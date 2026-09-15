local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

// One thermal board across the three device classes that report temperature:
// bare-metal Talos workers (cluster="tiles"), the Proxmox NUCs and raconteur
// (both cluster="bond"). Every selector, chip name and threshold comes from
// _config -- the same keys the bond-mixin alerts read -- so the board cannot
// drift away from what actually pages. See docs/monitoring-mixins.md for how
// this becomes a ConfigMap, and alerts/{metal,proxmox,raconteur}.libsonnet for
// the alerts these panels mirror.
{
  grafanaDashboards+:: {
    'bond-temperature.json':
      local cfg = $._config;
      local ds = '${' + cfg.datasourceName + '}';

      // Class selectors, matching the deployed alerts exactly.
      local metalSel = 'job="%(metalNodeExporterJob)s", cluster="%(metalCluster)s"' % cfg;
      local proxmoxSel = 'job="%(proxmoxNodeExporterJob)s", cluster="%(bondCluster)s", %(proxmoxInstanceSelector)s' % cfg;
      local raconteurSel = 'job="%(raconteurNodeExporterJob)s", cluster="%(bondCluster)s", instance="%(raconteurInstance)s"' % cfg;
      local snmpSel = 'cluster="%(bondCluster)s", job="%(raconteurSnmpJob)s"' % cfg;

      // The hwmon chip label is a hashed PCI path (k10temp, amdgpu) or a platform name
      // (coretemp), so a sensor class is selected by joining on node_hwmon_chip_names
      // rather than by chip. That is the same join alerts/metal.libsonnet uses: it needs
      // no node names, and auto-scopes to hosts that actually have the chip (VMs emit none).
      local byChip(metric, sel, chipNames) =
        '%s{%s} * on (instance, chip) group_left (chip_name) node_hwmon_chip_names{chip_name=~"%s"}'
        % [metric, sel, chipNames];

      // Hardware crit, with sentinel values dropped (see critSane* in config.libsonnet).
      local sane(expr) = '(%s) > %g < %g' % [expr, cfg.critSaneMinCelsius, cfg.critSaneMaxCelsius];

      // A Synology disk's type is an SNMP OctetString, hex-encoded on the label.
      local snmpDisk(diskType) =
        'diskTemperature{%(snmp)s} * on(diskIndex) group_left(diskType) diskType{%(snmp)s, diskType="%(t)s"}'
        % { snmp: snmpSel, t: diskType };

      // --- the sensor classes the overview table unions together ------------
      // `cur` and `crit` must carry an identical label set (instance, kind) so the four
      // table queries merge into one row per sensor. Both limits are nullable and for
      // different reasons: `crit: null` means the hardware reports no usable limit
      // (lancer's k10temp and amdgpu, the SNMP disks), `warn: null` means no bond-mixin
      // alert covers that sensor (the node_exporter storage temps). Neither borrows a
      // number from elsewhere -- a blank cell is the honest answer.
      local sensors = [
        {
          kind: 'CPU',
          warn: cfg.metalCpuTempThresholdCelsius,
          cur: 'max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', metalSel, cfg.metalCpuChipNames),
          crit: 'max by (instance) (%s)' % sane(byChip('node_hwmon_temp_crit_celsius', metalSel, cfg.metalCpuChipNames)),
        },
        {
          kind: 'iGPU',
          warn: cfg.metalGpuTempThresholdCelsius,
          cur: 'max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', metalSel, cfg.metalGpuChipNames),
          crit: 'max by (instance) (%s)' % sane(byChip('node_hwmon_temp_crit_celsius', metalSel, cfg.metalGpuChipNames)),
        },
        {
          kind: 'storage',
          warn: null,
          cur: 'max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', metalSel, cfg.metalStorageChipNames),
          crit: 'max by (instance) (%s)' % sane(byChip('node_hwmon_temp_crit_celsius', metalSel, cfg.metalStorageChipNames)),
        },
        {
          kind: 'CPU',
          warn: cfg.proxmoxCoreTempThresholdCelsius,
          // avg, not max: this mirrors BondProxmoxHighCoreTemperature, which averages the
          // coretemp package sensor with the per-core ones.
          cur: 'avg by (instance) (node_hwmon_temp_celsius{%s, chip="%s"})' % [proxmoxSel, cfg.proxmoxHwmonCoreChip],
          crit: 'max by (instance) (%s)' % sane('node_hwmon_temp_crit_celsius{%s, chip="%s"}' % [proxmoxSel, cfg.proxmoxHwmonCoreChip]),
        },
        {
          kind: 'storage',
          warn: null,
          cur: 'max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', proxmoxSel, cfg.proxmoxStorageChipNames),
          crit: 'max by (instance) (%s)' % sane(byChip('node_hwmon_temp_crit_celsius', proxmoxSel, cfg.proxmoxStorageChipNames)),
        },
        {
          kind: 'CPU',
          warn: cfg.raconteurCpuTempCelsius,
          cur: 'max by (instance) (node_hwmon_temp_celsius{%s, chip="%s"})' % [raconteurSel, cfg.raconteurCpuChip],
          crit: 'max by (instance) (%s)' % sane('node_hwmon_temp_crit_celsius{%s, chip="%s"}' % [raconteurSel, cfg.raconteurCpuChip]),
        },
        {
          // SNMP carries instance="prometheus.exporter.snmp.synology" (the Alloy component
          // that scraped it), not the host, so it is relabelled to line up with raconteur's
          // node_exporter rows. Per-disk detail is in the SNMP row below; the overview
          // carries one row per disk type so twelve disks do not swamp fourteen sensors.
          kind: 'SATA disk (hottest)',
          warn: cfg.raconteurDiskSataTempCelsius,
          cur: 'label_replace(max (%s), "instance", "%s", "", "")' % [snmpDisk(cfg.raconteurDiskTypeSata), cfg.raconteurInstance],
          crit: null,
        },
        {
          kind: 'SSD disk (hottest)',
          warn: cfg.raconteurDiskSsdTempCelsius,
          cur: 'label_replace(max (%s), "instance", "%s", "", "")' % [snmpDisk(cfg.raconteurDiskTypeSsd), cfg.raconteurInstance],
          crit: null,
        },
      ];

      local tagged(expr, kind) = 'label_replace(%s, "kind", "%s", "", "")' % [expr, kind];
      local union(parts) = std.join('\n  or\n', parts);

      local curUnion = union([tagged(s.cur, s.kind) for s in sensors]);
      // `* 0 + warn` gives the alert threshold the same labels as the reading it applies to,
      // so the table joins without naming a single host.
      local warnUnion = union([tagged('(%s) * 0 + %g' % [s.cur, s.warn], s.kind) for s in sensors if s.warn != null]);
      local critUnion = union([tagged(s.crit, s.kind) for s in sensors if s.crit != null]);
      local headroomUnion = union([tagged('%g - (%s)' % [s.warn, s.cur], s.kind) for s in sensors if s.warn != null]);

      // --- panel helpers ----------------------------------------------------
      local q(expr, legend) =
        g.query.prometheus.new(ds, expr)
        + g.query.prometheus.withLegendFormat(legend);

      local tq(expr, refId) =
        g.query.prometheus.new(ds, expr)
        + g.query.prometheus.withInstant(true)
        + g.query.prometheus.withFormat('table')
        + { refId: refId };

      // Alert threshold as a dashed red line (what pages), hardware crit as a dimmed
      // series (what the silicon says). Both are shown: they are different claims, and
      // on this fleet they disagree by as much as 15 C.
      local critOverride =
        g.panel.timeSeries.standardOptions.withOverrides([
          g.panel.timeSeries.standardOptions.override.byRegexp.new('/crit \\(hw\\)/')
          + g.panel.timeSeries.standardOptions.override.byRegexp.withProperty('color', { mode: 'fixed', fixedColor: 'text' })
          + g.panel.timeSeries.standardOptions.override.byRegexp.withProperty('custom.lineStyle', { fill: 'dash', dash: [10, 10] })
          + g.panel.timeSeries.standardOptions.override.byRegexp.withProperty('custom.fillOpacity', 0),
        ]);

      local ts(title, unit, targets, desc, warnAt=null) =
        g.panel.timeSeries.new(title)
        + g.panel.timeSeries.panelOptions.withDescription(desc)
        + g.panel.timeSeries.standardOptions.withUnit(unit)
        + g.panel.timeSeries.options.legend.withDisplayMode('table')
        + g.panel.timeSeries.options.legend.withPlacement('bottom')
        + g.panel.timeSeries.options.legend.withCalcs(['lastNotNull', 'max'])
        + g.panel.timeSeries.fieldConfig.defaults.custom.withFillOpacity(8)
        + g.panel.timeSeries.queryOptions.withTargets(targets)
        + (
          if warnAt == null then {}
          else
            g.panel.timeSeries.fieldConfig.defaults.custom.thresholdsStyle.withMode('dashed')
            + g.panel.timeSeries.standardOptions.thresholds.withMode('absolute')
            + g.panel.timeSeries.standardOptions.thresholds.withSteps([
              g.panel.timeSeries.standardOptions.threshold.step.withColor('text') + g.panel.timeSeries.standardOptions.threshold.step.withValue(null),
              g.panel.timeSeries.standardOptions.threshold.step.withColor('red') + g.panel.timeSeries.standardOptions.threshold.step.withValue(warnAt),
            ])
        );

      local pos(p, x, y, w, h) = p { gridPos: { x: x, y: y, w: w, h: h } };
      local rowAt(title, y) = g.panel.row.new(title) + { gridPos: { x: 0, y: y, w: 24, h: 1 } };

      // --- Overview ---------------------------------------------------------
      local tOverview = pos(
        g.panel.table.new('Every temperature sensor, against both of its limits')
        + g.panel.table.panelOptions.withDescription(|||
          One row per sensor across all three device classes, sorted by how close it is to
          firing. "alert at" is the deployed bond-mixin threshold -- the line that actually
          pages. "hw crit" is the shutdown limit the hardware reports for itself, shown only
          where it is real: lancer's k10temp CPU and amdgpu iGPU report none, and acebase's
          drivetemp reports the 127 C "unset" sentinel, so those cells are blank and the
          alert threshold is the only limit in play. The storage rows are the mirror case:
          no bond-mixin alert covers node_exporter storage temps, so "alert at" and the
          headroom are blank there and the hardware crit is the only limit. Where both
          exist they disagree -- an Intel package at 105 C crit has 15 C more room than the
          90 C alert implies, which is the whole reason both columns are here.
        |||)
        + g.panel.table.standardOptions.withUnit('celsius')
        + g.panel.table.queryOptions.withTargets([
          tq(curUnion, 'A'),
          tq(warnUnion, 'B'),
          tq(critUnion, 'C'),
          tq(headroomUnion, 'D'),
        ])
        + g.panel.table.queryOptions.withTransformations([
          { id: 'merge', options: {} },
          {
            id: 'organize',
            options: {
              excludeByName: { Time: true },
              renameByName: {
                instance: 'device',
                kind: 'sensor',
                'Value #A': 'now',
                'Value #B': 'alert at',
                'Value #C': 'hw crit',
                'Value #D': 'headroom to alert',
              },
              indexByName: {
                instance: 0,
                kind: 1,
                'Value #A': 2,
                'Value #D': 3,
                'Value #B': 4,
                'Value #C': 5,
              },
            },
          },
          { id: 'sortBy', options: { sort: [{ field: 'headroom to alert' }] } },
        ]),
        0,
        1,
        24,
        11
      );

      // --- CPU --------------------------------------------------------------
      local pMetalCpu = pos(ts(
        'Bare-metal CPU (cluster="%s")' % cfg.metalCluster,
        'celsius',
        [
          q('max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', metalSel, cfg.metalCpuChipNames), '{{instance}}'),
          q('max by (instance) (%s)' % sane(byChip('node_hwmon_temp_crit_celsius', metalSel, cfg.metalCpuChipNames)), '{{instance}} crit (hw)'),
        ],
        'Hottest CPU sensor per node -- lancer is AMD (k10temp), acebase Intel (coretemp). '
        + 'Red line is BondMetalHighCpuTemperature (%gC for %s). Only acebase reports a hardware crit; lancer k10temp reports none.'
          % [cfg.metalCpuTempThresholdCelsius, cfg.metalCpuTempFor],
        cfg.metalCpuTempThresholdCelsius
      ) + critOverride, 0, 13, 8, 8);

      local pProxmoxCpu = pos(ts(
        'Proxmox host cores',
        'celsius',
        [
          q('avg by (instance) (node_hwmon_temp_celsius{%s, chip="%s"})' % [proxmoxSel, cfg.proxmoxHwmonCoreChip], '{{instance}}'),
          q('max by (instance) (%s)' % sane('node_hwmon_temp_crit_celsius{%s, chip="%s"}' % [proxmoxSel, cfg.proxmoxHwmonCoreChip]), '{{instance}} crit (hw)'),
        ],
        'Average coretemp per host, matching BondProxmoxHighCoreTemperature (%gC for %s) -- which averages the package sensor with the per-core ones, so a single hot core is diluted here. All four NUCs report a 105C hardware crit.'
        % [cfg.proxmoxCoreTempThresholdCelsius, cfg.proxmoxCoreTempFor],
        cfg.proxmoxCoreTempThresholdCelsius
      ) + critOverride, 8, 13, 8, 8);

      local pRaconteurCpu = pos(ts(
        'Raconteur CPU',
        'celsius',
        [
          q('max by (sensor) (node_hwmon_temp_celsius{%s, chip="%s"})' % [raconteurSel, cfg.raconteurCpuChip], '{{sensor}}'),
          q('max (%s)' % sane('node_hwmon_temp_crit_celsius{%s, chip="%s"}' % [raconteurSel, cfg.raconteurCpuChip]), 'crit (hw)'),
        ],
        'Per-sensor coretemp on the Synology. Red line is BondRaconteurCpuTemperatureHigh (%gC for %s) -- set well below the 104C the hardware reports as its own crit, because a NAS that is merely warm is already a fan or airflow problem.'
        % [cfg.raconteurCpuTempCelsius, cfg.raconteurCpuTempFor],
        cfg.raconteurCpuTempCelsius
      ) + critOverride, 16, 13, 8, 8);

      // --- iGPU and storage -------------------------------------------------
      local pGpu = pos(ts(
        'lancer iGPU (amdgpu)',
        'celsius',
        [q('max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', metalSel, cfg.metalGpuChipNames), '{{instance}}')],
        'Integrated GPU temperature. Only AMD APUs expose a GPU hwmon, so this is lancer-only today and will pick up any future AMD-GPU node on its own. amdgpu reports no crit, so the %gC BondMetalHighGpuTemperature line is the only limit -- set above the CPU because an APU GPU legitimately runs hotter under ROCm/ODM load.'
        % cfg.metalGpuTempThresholdCelsius,
        cfg.metalGpuTempThresholdCelsius
      ), 0, 22, 8, 8);

      local pStorage = pos(ts(
        'Storage sensors (NVMe, SATA drivetemp)',
        'celsius',
        [
          q('max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', metalSel, cfg.metalStorageChipNames), '{{instance}} (metal)'),
          q('max by (instance) (%s)' % byChip('node_hwmon_temp_celsius', proxmoxSel, cfg.proxmoxStorageChipNames), '{{instance}} (proxmox)'),
          q('max by (instance) (%s)' % sane(byChip('node_hwmon_temp_crit_celsius', metalSel, cfg.metalStorageChipNames)), '{{instance}} crit (hw)'),
          q('max by (instance) (%s)' % sane(byChip('node_hwmon_temp_crit_celsius', proxmoxSel, cfg.proxmoxStorageChipNames)), '{{instance}} crit (hw)'),
        ],
        'Hottest storage sensor per host. No alert covers these -- the hardware crit (94.85C on every NVMe here) is the only limit, which is why it is drawn rather than a fixed line. Two absences are real, not gaps: the g2p NUCs expose no NVMe hwmon at all, and acebase reports the 127C drivetemp sentinel instead of a limit.'
      ) + critOverride, 8, 22, 16, 8);

      // --- Raconteur disks --------------------------------------------------
      local pSata = pos(ts(
        'Raconteur SATA disks (SNMP)',
        'celsius',
        [q(snmpDisk(cfg.raconteurDiskTypeSata), 'disk {{diskIndex}}')],
        'Per-disk temperature from the Synology SNMP feed, filtered to SATA by the hex-encoded diskType OctetString. Red line is BondRaconteurSataDiskTemperatureHigh (%gC for %s). SNMP reports no per-disk limit, so the alert threshold is the only reference.'
        % [cfg.raconteurDiskSataTempCelsius, cfg.raconteurDiskSataTempFor],
        cfg.raconteurDiskSataTempCelsius
      ), 0, 31, 12, 8);

      local pSsd = pos(ts(
        'Raconteur SSD disks (SNMP)',
        'celsius',
        [q(snmpDisk(cfg.raconteurDiskTypeSsd), 'disk {{diskIndex}}')],
        'As above for the SSDs, against BondRaconteurSsdDiskTemperatureHigh (%gC for %s) -- a higher line than the SATA one because flash tolerates more heat than spinning rust.'
        % [cfg.raconteurDiskSsdTempCelsius, cfg.raconteurDiskSsdTempFor],
        cfg.raconteurDiskSsdTempCelsius
      ), 12, 31, 12, 8);

      // --- Throttle response ------------------------------------------------
      // `and on (instance) count(node_hwmon_temp_celsius)` restricts these to physical
      // hosts: the tiles VMs also expose Processor cooling devices and scaling frequency,
      // but have no thermal story, and would otherwise pad every series list.
      local physical = 'and on (instance) (count by (instance) (node_hwmon_temp_celsius))';

      local pCooling = pos(ts(
        'Passive throttle state',
        'short',
        [q('max by (instance, type) (node_cooling_device_cur_state{type=~"%s"} %s)' % [cfg.coolingDeviceTypes, physical], '{{instance}} {{type}}')],
        'Current cooling-device step, 0 = not throttling. This is the response to heat rather than the heat itself: a temperature that stops climbing while this rises is the machine protecting itself, not a sensor that settled. The step scales are not comparable across the series: Processor devices expose 3 steps (raconteur 10) while intel_powerclamp runs 0-100, so read movement off zero rather than the absolute number.'
      ), 0, 40, 8, 8);

      local pFreq = pos(ts(
        'CPU frequency vs reported max',
        'percentunit',
        [q('avg by (instance) (node_cpu_scaling_frequency_hertz / node_cpu_scaling_frequency_max_hertz) %s' % physical, '{{instance}}')],
        'Mean core frequency as a fraction of the cpufreq maximum -- a rough throttle proxy. Rough in both directions: it reads above 1.0 on raconteur, whose reported max excludes turbo, so compare a host against its own history rather than against the other hosts or against 1.0.'
      ), 8, 40, 8, 8);

      local pPower = pos(ts(
        'lancer APU package power',
        'watt',
        [q('sum by (instance) (node_hwmon_power_watt{%s})' % metalSel, '{{instance}}')],
        'Power draw reported by lancer amdgpu -- the only power sensor on the fleet. Useful read alongside the iGPU temperature: power up with temperature flat is healthy cooling, temperature up with power flat is a cooling problem.'
      ), 16, 40, 8, 8);

      g.dashboard.new(cfg.dashboardTitle)
      + g.dashboard.withUid(cfg.dashboardUid)
      + g.dashboard.withTags(cfg.dashboardTags)
      + g.dashboard.withTimezone(cfg.dashboardTimezone)
      + g.dashboard.withRefresh(cfg.dashboardRefresh)
      + g.dashboard.withEditable(false)
      + g.dashboard.withDescription(
        'Temperature across every device class that reports one: bare-metal Talos workers, '
        + 'the Proxmox hosts and raconteur. Thresholds are read from the bond-mixin config, '
        + 'so this board and the alerts cannot disagree.'
      )
      + g.dashboard.time.withFrom(cfg.dashboardPeriod)
      + g.dashboard.time.withTo('now')
      + g.dashboard.withVariables([
        g.dashboard.variable.datasource.new(cfg.datasourceName, 'prometheus')
        + g.dashboard.variable.datasource.generalOptions.withLabel('Data source'),
      ])
      + g.dashboard.withPanels([
        rowAt('Overview -- every sensor against its limits', 0),
        tOverview,
        rowAt('CPU', 12),
        pMetalCpu,
        pProxmoxCpu,
        pRaconteurCpu,
        rowAt('iGPU and storage', 21),
        pGpu,
        pStorage,
        rowAt('Raconteur disks (SNMP)', 30),
        pSata,
        pSsd,
        rowAt('Throttle response', 39),
        pCooling,
        pFreq,
        pPower,
      ]),
  },
}
