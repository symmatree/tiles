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
  local kEnvVar = k.core.v1.envVar,
  local kConfigMap = k.core.v1.configMap,

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
    tcpHostname: APP.app_settings.tcp_hostname,
    ntripCaster: APP.app_settings.ntrip_caster,
    ntripMountpoint: APP.app_settings.ntrip_mountpoint,
    ntripPort: 2101,
    ntripSecret: APP.app_settings.ntrip_caster_auth,
    sourceSystem: 255,
    sourceComponent: 190,

    // Namespace of this environment (environments/mavproxy/spec.json). Needed as a
    // literal because the Probe's prober URL is resolved by Alloy, in the alloy
    // namespace, so it has to be fully qualified.
    namespace: 'mavproxy',
    jsonExporterName: 'json-exporter',
    jsonExporterImage: APP.app_settings.json_exporter_image,
    jsonExporterPort: 7979,
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
        + kContainer.withEnvMixin([
          kEnvVar.new('NTRIP_CASTER', config.ntripCaster),
          kEnvVar.new('NTRIP_PORT', std.toString(config.ntripPort)),
          kEnvVar.new('NTRIP_MOUNTPOINT', config.ntripMountpoint),
          kEnvVar.fromSecretRef('NTRIP_USERNAME', ntripSecretName, 'username'),
          kEnvVar.fromSecretRef('NTRIP_PASSWORD', ntripSecretName, 'password'),
        ])
        + kContainer.withArgs([
          std.format('--master=udpin:0.0.0.0:%s', config.mavlinkUdpPort),
          std.format('--out=tcpin:0.0.0.0:%s', config.tcpPort),
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
    // endpoint is the only way to trend it. json_exporter maps the JSON fields to
    // metrics; Alloy scrapes it multi-target style through the Probe below. This
    // is the backpack<->AP link, which mavproxy never sees -- orthogonal to FC
    // telemetry.
    local jsonExporterLabels = { app: config.jsonExporterName },

    jsonExporterConfig:
      kConfigMap.new(config.jsonExporterName)
      + kConfigMap.metadata.withLabels(jsonExporterLabels)
      + kConfigMap.withData({
        'config.yml': |||
          ---
          modules:
            backpack:
              metrics:
                - name: backpack_mavlink_enabled
                  help: 1 when the backpack WiFi service is the MAVLink bridge (Telem mode = WiFi).
                  path: '{ .enabled }'
                  valuetype: gauge
                - name: backpack_wifi_rssi_dbm
                  help: Backpack-to-AP RSSI reported by the esp8285.
                  path: '{ .link.rssi }'
                  valuetype: gauge
                - name: backpack_wifi_reconnects_total
                  help: STA reconnects since boot -- rising while still reachable means the reconnect patch is riding out drops instead of falling back to AP mode.
                  path: '{ .link.reconnects }'
                  valuetype: counter
                - name: backpack_uptime_milliseconds
                  help: millis() since backpack boot; a drop to near zero is a reboot.
                  path: '{ .link.uptime_ms }'
                  valuetype: gauge
                - name: backpack_mavlink_packets_up_total
                  help: MAVLink packets bridged uplink (ground -> air), including RTCM.
                  path: '{ .counters.packets_up }'
                  valuetype: counter
                - name: backpack_mavlink_packets_down_total
                  help: MAVLink packets bridged downlink (air -> ground).
                  path: '{ .counters.packets_down }'
                  valuetype: counter
                - name: backpack_mavlink_drops_down_total
                  help: Downlink drops counted by the backpack; a per-source sequence artifact, not necessarily real loss.
                  path: '{ .counters.drops_down }'
                  valuetype: counter
                - name: backpack_mavlink_overflows_down_total
                  help: Downlink buffer overflows -- genuine link-capacity pressure.
                  path: '{ .counters.overflows_down }'
                  valuetype: counter
                - name: backpack_wifi_link
                  help: WiFi association the backpack is on; value is always 1.
                  type: object
                  valuetype: gauge
                  path: '{ .link }'
                  labels:
                    ssid: '{ .ssid }'
                    bssid: '{ .bssid }'
                  values:
                    info: 1
                - name: backpack_mavlink_gcs
                  help: GCS the backpack has latched onto; value is always 1. "IP UNSET" means it is still broadcasting.
                  type: object
                  valuetype: gauge
                  path: '{ .ip }'
                  labels:
                    gcs: '{ .gcs }'
                  values:
                    info: 1
        |||,
      }),

    jsonExporterDeployment:
      kDeployment.new(config.jsonExporterName, replicas=1, containers=[
        kContainer.new(config.jsonExporterName, config.jsonExporterImage)
        + kContainer.withArgs(['--config.file=/etc/json_exporter/config.yml'])
        + kContainer.withPortsMixin([
          kPort.newNamed(config.jsonExporterPort, 'http'),
        ])
        + kContainer.resources.withRequests({ memory: '32Mi' })
        + kContainer.resources.withLimits({ memory: '64Mi' })
        + readinessProbe.httpGet.withPath('/')
        + readinessProbe.httpGet.withPort(config.jsonExporterPort),
      ], podLabels=jsonExporterLabels)
      + kDeployment.spec.selector.withMatchLabels(jsonExporterLabels)
      // Adds the volume, the mount, and a config-hash pod annotation so a config
      // edit actually rolls the pod (json_exporter reads its config at startup).
      + k_util.configMapVolumeMount(mavproxyObj.jsonExporterConfig, '/etc/json_exporter'),

    jsonExporterService:
      k_util.serviceFor(mavproxyObj.jsonExporterDeployment),

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
          url: '%s.%s.svc:%d' % [config.jsonExporterName, config.namespace, config.jsonExporterPort],
          path: '/probe',
        },
        targets: {
          staticConfig: {
            static: [config.backpackMavlinkUrl],
          },
        },
      },
    },

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
  },
};

mavproxy.new({})
