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

local ntrip = {
  local kDeployment = k.apps.v1.deployment,
  local kContainer = k.core.v1.container,
  local kPort = k.core.v1.containerPort,
  local kPersistentVolumeClaim = k.core.v1.persistentVolumeClaim,
  local kIngress = k.networking.v1.ingress,
  local kEnvVar = k.core.v1.envVar,
  local kIngressRule = k.networking.v1.ingressRule,
  local kHttpIngressPath = k.networking.v1.httpIngressPath,
  local kIngressTLS = k.networking.v1.ingressTLS,

  local gnssToleration = {
    key: 'dedicated',
    operator: 'Equal',
    value: 'gnss',
    effect: 'NoSchedule',
  },

  local defaults = {
    name: 'rtkbase',
    image: APP.app_settings.image,
    webPort: kPort.newNamed(80, 'http'),
    ntripPortName: 'ntrip',
    ntripPortNumber: 2101,
    ntripHostname: APP.app_settings.ntrip_hostname,
    adminHostname: APP.app_settings.admin_hostname,
    adminSecret: APP.app_settings.ntrip_admin,
    casterSecret: APP.app_settings.ntrip_caster_auth,
    ingressAnnotations: {
      'cert-manager.io/cluster-issuer': APP.app_settings.cluster_issuer,
    },
    ingressClassName: 'cilium',
  },

  new(overrides):: {
    local ntripObj = self,
    local config = defaults + overrides,

    adminSecret: op.item.new(config.adminSecret, 'vaults/' + APP.vault_name + '/items/' + config.adminSecret),
    casterSecret: op.item.new(config.casterSecret, 'vaults/' + APP.vault_name + '/items/' + config.casterSecret),

    persistPvc: kPersistentVolumeClaim.new(std.format('%s-persist', config.name))
                + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteOnce'])
                + kPersistentVolumeClaim.spec.resources.withRequestsMixin({ storage: '5Gi' })
                + kPersistentVolumeClaim.spec.withStorageClassName('local-path'),

    local podLabels = { app: config.name },

    deployment:
      kDeployment.new(config.name, replicas=1, containers=[
        kContainer.new(config.name, config.image)
        + kContainer.withPortsMixin([
          config.webPort,
          kPort.newNamed(config.ntripPortNumber, config.ntripPortName),
        ])
        + kContainer.withEnvMixin([
          kEnvVar.new('RTKBASE_WEB_PASSWORD', '')
          + kEnvVar.valueFrom.secretKeyRef.withName(ntripObj.adminSecret.metadata.name)
          + kEnvVar.valueFrom.secretKeyRef.withKey('password'),
          kEnvVar.new('RTKBASE_NTRIP_USER', '')
          + kEnvVar.valueFrom.secretKeyRef.withName(ntripObj.casterSecret.metadata.name)
          + kEnvVar.valueFrom.secretKeyRef.withKey('username'),
          kEnvVar.new('RTKBASE_NTRIP_PASSWORD', '')
          + kEnvVar.valueFrom.secretKeyRef.withName(ntripObj.casterSecret.metadata.name)
          + kEnvVar.valueFrom.secretKeyRef.withKey('password'),
        ])
        + kContainer.securityContext.withPrivileged(true),
      ], podLabels=podLabels)
      + kDeployment.spec.selector.withMatchLabels(podLabels)
      + kDeployment.spec.strategy.withType('Recreate')
      + kDeployment.spec.template.spec.withNodeSelector({ 'kubernetes.io/hostname': 'acebase' })
      + kDeployment.spec.template.spec.withTolerationsMixin([gnssToleration])
      + k_util.pvcVolumeMount(ntripObj.persistPvc.metadata.name, '/persist/rtkbase')
      + k_util.hostVolumeMount('gnss', '/dev/gnss', '/dev/gnss')
      + k_util.hostVolumeMount('cgroup', '/sys/fs/cgroup', '/sys/fs/cgroup', readOnly=false),

    webService: k_util.serviceFor(self.deployment),

    ntripCasterService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'ntrip-caster',
        annotations: {
          'external-dns.alpha.kubernetes.io/hostname': config.ntripHostname,
        },
        labels: podLabels,
      },
      spec: {
        type: 'LoadBalancer',
        selector: podLabels,
        ports: [{
          name: 'ntrip',
          port: config.ntripPortNumber,
          targetPort: config.ntripPortNumber,
          protocol: 'TCP',
        }],
      },
    },

    ingress:
      kIngress.new(std.format('%s-admin', config.name))
      + kIngress.metadata.withAnnotations(config.ingressAnnotations)
      + kIngress.spec.withIngressClassName(config.ingressClassName)
      + kIngress.spec.withRulesMixin([
        kIngressRule.withHost(config.adminHostname)
        + kIngressRule.http.withPathsMixin(
          kHttpIngressPath.withPath('/')
          + kHttpIngressPath.withPathType('Prefix')
          + kHttpIngressPath.backend.service.withName(ntripObj.webService.metadata.name)
          + kHttpIngressPath.backend.service.port.withName(ntripObj.webService.spec.ports[0].name)
        ),
      ])
      + kIngress.spec.withTlsMixin([
        kIngressTLS.withHosts([config.adminHostname])
        + kIngressTLS.withSecretName(std.format('%s-admin-tls', config.name)),
      ]),
  },
};

ntrip.new({})
