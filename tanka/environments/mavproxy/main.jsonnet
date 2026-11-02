local k_util = import 'github.com/grafana/jsonnet-libs/ksonnet-util/util.libsonnet';
local k = import 'k.libsonnet';
local op = import 'op.libsonnet';

local APP_VARS = std.parseJson(std.extVar('ARGOCD_APP_PARAMETERS'));
local isString(v) = std.objectHas(v, 'string');
local isMap(v) = std.objectHas(v, 'map');
local APP = {
  [v.name]: v.string
  for v in std.filter(isString, APP_VARS)
} + {
  [v.name]: v.map
  for v in std.filter(isMap, APP_VARS)
};

local mavproxy = {
  local kDeployment = k.apps.v1.deployment,
  local kContainer = k.core.v1.container,
  local kPort = k.core.v1.containerPort,
  local kConfigMap = k.core.v1.configMap,
  local kPersistentVolume = k.core.v1.persistentVolume,
  local kPersistentVolumeClaim = k.core.v1.persistentVolumeClaim,
  local kEnvVar = k.core.v1.envVar,

  local gnssToleration = {
    key: 'dedicated',
    operator: 'Equal',
    value: 'gnss',
    effect: 'NoSchedule',
  },

  local defaults = {
    name: 'mavproxy',
    image: APP.app_settings.image,
    nodeHostname: 'acebase',
    mavlinkUdpPort: 14550,
    tcpPort: 5760,
    // A second fan-out, for tlog-split: a `udpout` from mavproxy to the tlog-split Service.
    // UDP, not a `tcpin`, because `tcpin` holds one client and never re-accepts until that
    // client errors on a write -- see TLOG-SPLIT.md for the month that cost.
    splitPort: 5761,
    splitService: 'tlog-split',
    // spec.json's namespace, which jsonnet cannot read; the udpout target has to name it.
    namespace: 'mavproxy',
    tcpHostname: APP.app_settings.tcp_hostname,
    ntripCaster: APP.app_settings.ntrip_caster,
    ntripMountpoint: APP.app_settings.ntrip_mountpoint,
    ntripPort: 2101,
    ntripSecret: APP.app_settings.ntrip_caster_auth,
    sourceSystem: 255,
    sourceComponent: 190,

    // The mLRS link: a RadioMaster Ranger on mLRS, USB-C into acebase, to the RP4TD on the FC's
    // SERIAL7 (coordinator ardupilot/inputs/mlrs-link.param). This instance carries the RTCM;
    // the backpack instance above only logs. /dev/mlrs is the udev symlink from
    // tf/nodes/patches/acebase-gnss.yaml; 115200 is the module's "Tx Ser Baudrate".
    mlrsName: 'mavproxy-mlrs',
    mlrsDevice: '/dev/mlrs',
    mlrsBaud: 115200,
    mlrsTcpPort: 5770,
    mlrsTcpHostname: APP.app_settings.mlrs_tcp_hostname,
    mlrsSplitService: 'tlog-split-mlrs',
    mlrsSplitPort: 5762,

    // Shared json_exporter prober, deployed with the Alloy app in the alloy
    // namespace (charts/argocd-applications/templates/alloy-application.yaml).
    jsonExporterProber: 'json-exporter.alloy.svc:7979',
    backpackMavlinkUrl: APP.app_settings.backpack_mavlink_url,
    // 30s, not 5s: the backpack is a single-threaded esp8285 on a marginal link
    // (coordinator#190). Alloy's default scrape timeout (10s) applies, so a
    // backpack that is off or off-network just yields up=0 for that interval.
    backpackScrapeInterval: '30s',
  },

  new(overrides):: {
    local mavproxyObj = self,
    local config = defaults + overrides,

    ntripSecret: op.item.new(config.ntripSecret, 'vaults/' + APP.vault_name + '/items/' + config.ntripSecret),

    local podLabels = { app: config.name },
    local ntripSecretName = mavproxyObj.ntripSecret.metadata.name,
    local ntripEnv = [
      kEnvVar.new('NTRIP_CASTER', config.ntripCaster),
      kEnvVar.new('NTRIP_PORT', std.toString(config.ntripPort)),
      kEnvVar.new('NTRIP_MOUNTPOINT', config.ntripMountpoint),
      kEnvVar.fromSecretRef('NTRIP_USERNAME', ntripSecretName, 'username'),
      kEnvVar.fromSecretRef('NTRIP_PASSWORD', ntripSecretName, 'password'),
    ],

    local execProbe(probe) =
      probe.withInitialDelaySeconds(10)
      + probe.withPeriodSeconds(10)
      + probe.withTimeoutSeconds(1)
      + probe.withSuccessThreshold(1)
      + probe.exec.withCommand(['/bin/sh', '-c', 'kill -0 1']),
    local readinessProbe = kContainer.readinessProbe,

    deployment:
      kDeployment.new(config.name, replicas=1, containers=[
        kContainer.new(config.name, config.image)
        + kContainer.withImagePullPolicy('Always')
        + kContainer.withPortsMixin([
          kPort.newNamedUDP(config.mavlinkUdpPort, 'mavlink-udp'),
          kPort.newNamed(config.tcpPort, 'mavlink-tcp'),
        ])
        // No NTRIP env: this instance only logs the ELRS link. Without NTRIP_CASTER the
        // entrypoint writes no mavinit.scr, so the ntrip module below loads and is never
        // started -- RTCM goes up the mLRS link from the mlrs instance instead.
        + kContainer.withArgs([
          std.format('--master=udpin:0.0.0.0:%s', config.mavlinkUdpPort),
          std.format('--out=tcpin:0.0.0.0:%s', config.tcpPort),
          // The pod is hostNetwork with ClusterFirstWithHostNet, so the Service name
          // resolves from it; pymavlink resolves the udpout target on every send.
          std.format('--out=udpout:%s.%s.svc:%s', [config.splitService, config.namespace, config.splitPort]),
          std.format('--source-system=%s', config.sourceSystem),
          std.format('--source-component=%s', config.sourceComponent),
          '--default-modules=ntrip',
          '--daemon',
          '--nowait',
        ])
        + execProbe(readinessProbe)
        + readinessProbe.withFailureThreshold(3),
      ], podLabels=podLabels)
      + kDeployment.spec.selector.withMatchLabels(podLabels)
      + kDeployment.spec.strategy.withType('Recreate')
      + kDeployment.spec.template.spec.withHostNetwork(true)
      + kDeployment.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet')
      + kDeployment.spec.template.spec.withNodeSelector({ 'kubernetes.io/hostname': config.nodeHostname })
      + kDeployment.spec.template.spec.withTolerationsMixin([gnssToleration]),

    // ---- backpack link health (coordinator#190) ------------------------------
    // The patched ELRS TX backpack reports its WiFi link health only on its own
    // HTTP endpoint (GET /mavlink), never in the MAVLink channel, so scraping that
    // endpoint is the only way to trend it. This is the backpack<->AP link, which
    // mavproxy never sees -- orthogonal to FC telemetry. The JSON-to-metrics
    // mapping (module `backpack`) lives in the shared json_exporter with the rest
    // of the probe plumbing; only this per-device Probe belongs here.
    // Scraped by Alloy (prometheusOperatorObjects discovers Probes in every
    // namespace). jobName pins job="backpack"; instance becomes the target URL.
    // Expect frequent up=0 -- the backpack is only on WiFi when the radio is on
    // and in Telem=WiFi mode -- that gap IS the availability signal, not an error.
    backpackProbe: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'Probe',
      metadata: {
        name: 'backpack-mavlink',
        labels: { 'app.kubernetes.io/name': 'backpack-mavlink' },
      },
      spec: {
        jobName: 'backpack',
        interval: config.backpackScrapeInterval,
        module: 'backpack',
        prober: {
          url: config.jsonExporterProber,
          path: '/probe',
        },
        targets: {
          staticConfig: {
            static: [config.backpackMavlinkUrl],
          },
        },
      },
    },

    // ---- tlog-split: one tlog per flight -------------------------------------------------
    // mavproxy cannot rotate its own log (coordinator#192, and TLOG-SPLIT.md for why
    // `--aircraft` is not the answer), so a second consumer writes per-flight files. It lives
    // here rather than in its own environment because it is meaningless without this mavproxy,
    // which is what sends to it.

    // Where mavproxy's udpout lands. tlog-split is the listener, so a restart on either side
    // costs nothing: nobody holds a connection.
    local splitServiceFor(name, port) = {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: { name: name, labels: { name: name } },
      spec: {
        type: 'ClusterIP',
        selector: { name: name },
        ports: [{
          name: 'mavlink-split',
          port: port,
          targetPort: port,
          protocol: 'UDP',
        }],
      },
    },
    splitService: splitServiceFor(config.splitService, config.splitPort),

    // Straight to the NAS, so a flight's ground-side record does not live or die with a pod.
    // Static PV for the same reason flight-analysis and fleet-control use one: `datasets` is a
    // different export from the one cluster-nfs provisions into.
    tlogPv:
      kPersistentVolume.new('ground-tlogs')
      + kPersistentVolume.spec.withCapacity({ storage: '200Gi' })
      + kPersistentVolume.spec.withAccessModes(['ReadWriteMany'])
      + kPersistentVolume.spec.withPersistentVolumeReclaimPolicy('Retain')
      + kPersistentVolume.spec.nfs.withServer(APP.app_settings.nfs_server)
      + kPersistentVolume.spec.nfs.withPath(APP.app_settings.datasets_nfs_path + '/ground-tlogs'),

    tlogPvc:
      kPersistentVolumeClaim.new('ground-tlogs')
      + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteMany'])
      + kPersistentVolumeClaim.spec.resources.withRequests({ storage: '200Gi' })
      + kPersistentVolumeClaim.spec.withVolumeName('ground-tlogs')
      + kPersistentVolumeClaim.spec.withStorageClassName(''),

    // The script, not an image. mavproxy's image already carries python3 and pymavlink --
    // MAVProxy depends on pymavlink -- and flight-analysis already mounts its runner.py from a
    // ConfigMap rather than building an image for it.
    splitScript:
      kConfigMap.new('tlog-split')
      + kConfigMap.withData({ 'split_tlog.py': importstr 'split_tlog.py' }),

    local splitDeploymentFor(name, port, outDir) =
      kDeployment.new(name, replicas=1, containers=[
        kContainer.new('tlog-split', config.image)
        + kContainer.withImagePullPolicy('Always')
        + kContainer.withCommand(['/opt/venv/bin/python3', '-u', '/script/split_tlog.py'])
        + kContainer.withPortsMixin([kPort.newNamedUDP(port, 'mavlink-split')])
        + kContainer.withEnvMap({
          TLOG_SPLIT_LISTEN: std.format('0.0.0.0:%s', port),
          TLOG_SPLIT_OUT: outDir,
        })
        // Small: it parses frames and appends to a file. No buffering of a lead-in, which is
        // what cutting at disarm rather than arm buys.
        + kContainer.resources.withRequests({ cpu: '25m', memory: '64Mi' })
        + kContainer.resources.withLimits({ memory: '128Mi' }),
      ])
      // Recreate, not RollingUpdate: two writers would interleave frames into two files and
      // neither would be one flight.
      + kDeployment.spec.strategy.withType('Recreate')
      // Roll when the image digest moves, like the other floating-tag workloads here.
      + kDeployment.metadata.withAnnotationsMixin({
        'tiles.symmatree.com/roll-on-digest-change': 'true',
      })
      // Editing the script has to restart it, or the change sits in the ConfigMap doing
      // nothing until something else happens to roll the pod.
      + kDeployment.mixin.spec.template.metadata.withAnnotationsMixin({
        'tlog-split-hash': std.md5(importstr 'split_tlog.py'),
      })
      + k_util.pvcVolumeMount('ground-tlogs', '/mnt/ground-tlogs')
      + k_util.configMapVolumeMount(self.splitScript, '/script'),

    splitDeployment: splitDeploymentFor(config.splitService, config.splitPort, '/mnt/ground-tlogs'),

    tcpService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'mavproxy-tcp',
        annotations: {
          'external-dns.alpha.kubernetes.io/hostname': config.tcpHostname,
        },
        labels: podLabels,
      },
      spec: {
        type: 'LoadBalancer',
        externalTrafficPolicy: 'Local',
        selector: podLabels,
        ports: [{
          name: 'mavlink-tcp',
          port: config.tcpPort,
          targetPort: config.tcpPort,
          protocol: 'TCP',
        }],
      },
    },

    // ---- the mLRS link: RTCM up, telemetry down ------------------------------------------
    // Not hostNetwork: nothing arrives by broadcast here, so it is an ordinary pod pinned to
    // acebase for the device. Privileged for the host device node, as the ntrip pod is for
    // /dev/gnss. --default-modules=ntrip as above, so no param module and no parameter fetch.
    // --streamrate=-1: send no REQUEST_DATA_STREAM; the FC's MAV4 rates are pinned in
    // mlrs-link.param and MAV4_OPTIONS ignores stream requests anyway.
    local mlrsLabels = { app: config.mlrsName },
    mlrsDeployment:
      kDeployment.new(config.mlrsName, replicas=1, containers=[
        kContainer.new(config.mlrsName, config.image)
        + kContainer.withImagePullPolicy('Always')
        + kContainer.withPortsMixin([
          kPort.newNamed(config.mlrsTcpPort, 'mavlink-tcp'),
        ])
        + kContainer.withEnvMixin(ntripEnv)
        + kContainer.withArgs([
          std.format('--master=%s,%s', [config.mlrsDevice, config.mlrsBaud]),
          std.format('--out=tcpin:0.0.0.0:%s', config.mlrsTcpPort),
          std.format('--out=udpout:%s.%s.svc:%s', [config.mlrsSplitService, config.namespace, config.mlrsSplitPort]),
          std.format('--source-system=%s', config.sourceSystem),
          std.format('--source-component=%s', config.sourceComponent),
          '--default-modules=ntrip',
          '--streamrate=-1',
          '--daemon',
          '--nowait',
        ])
        + kContainer.securityContext.withPrivileged(true)
        + execProbe(readinessProbe)
        + readinessProbe.withFailureThreshold(3),
      ], podLabels=mlrsLabels)
      + kDeployment.spec.selector.withMatchLabels(mlrsLabels)
      + kDeployment.spec.strategy.withType('Recreate')
      + kDeployment.spec.template.spec.withNodeSelector({ 'kubernetes.io/hostname': config.nodeHostname })
      + kDeployment.spec.template.spec.withTolerationsMixin([gnssToleration])
      + k_util.hostVolumeMount('mlrs', config.mlrsDevice, config.mlrsDevice),

    // Its own tlog-split, writing under mlrs/: both links cut at the same disarm, so the two
    // streams would otherwise produce files with the same names in the same directory.
    mlrsSplitService: splitServiceFor(config.mlrsSplitService, config.mlrsSplitPort),
    mlrsSplitDeployment: splitDeploymentFor(config.mlrsSplitService, config.mlrsSplitPort, '/mnt/ground-tlogs/mlrs'),

    mlrsTcpService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'mavproxy-mlrs-tcp',
        annotations: {
          'external-dns.alpha.kubernetes.io/hostname': config.mlrsTcpHostname,
        },
        labels: mlrsLabels,
      },
      spec: {
        type: 'LoadBalancer',
        externalTrafficPolicy: 'Local',
        selector: mlrsLabels,
        ports: [{
          name: 'mavlink-tcp',
          port: config.mlrsTcpPort,
          targetPort: config.mlrsTcpPort,
          protocol: 'TCP',
        }],
      },
    },
  },
};

mavproxy.new({})
