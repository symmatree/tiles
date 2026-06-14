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
  },

  new(overrides):: {
    local mavproxyObj = self,
    local config = defaults + overrides,

    ntripSecret: op.item.new(config.ntripSecret, 'vaults/' + APP.vault_name + '/items/' + config.ntripSecret),

    local podLabels = { app: config.name },
    local ntripSecretName = mavproxyObj.ntripSecret.metadata.name,

    local tcpProbe(probe, port) =
      probe.withInitialDelaySeconds(10)
      + probe.withPeriodSeconds(10)
      + probe.tcpSocket.withPort(port)
      + probe.withSuccessThreshold(1),
    local livenessProbe = kContainer.livenessProbe,
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
        + tcpProbe(readinessProbe, config.tcpPort)
        + readinessProbe.withFailureThreshold(3)
        + tcpProbe(livenessProbe, config.tcpPort)
        + livenessProbe.withInitialDelaySeconds(30)
        + livenessProbe.withPeriodSeconds(30)
        + livenessProbe.withFailureThreshold(6),
      ], podLabels=podLabels)
      + kDeployment.spec.selector.withMatchLabels(podLabels)
      + kDeployment.spec.strategy.withType('Recreate')
      + kDeployment.spec.template.spec.withHostNetwork(true)
      + kDeployment.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet')
      + kDeployment.spec.template.spec.withNodeSelector({ 'kubernetes.io/hostname': config.nodeHostname })
      + kDeployment.spec.template.spec.withTolerationsMixin([gnssToleration]),

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
