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

local fleetControl = {
  local kDeployment = k.apps.v1.deployment,
  local kContainer = k.core.v1.container,
  local kPort = k.core.v1.containerPort,
  local kConfigMap = k.core.v1.configMap,
  local kVolumeMount = k.core.v1.volumeMount,
  local kPersistentVolumeClaim = k.core.v1.persistentVolumeClaim,
  local kIngress = k.networking.v1.ingress,
  local kIngressRule = k.networking.v1.ingressRule,
  local kHttpIngressPath = k.networking.v1.httpIngressPath,
  local kIngressTLS = k.networking.v1.ingressTLS,

  local defaults = {
    name: 'fleet-control',
    image: APP.app_settings.image,
    port: kPort.newNamed(8080, 'http'),
    host: APP.app_settings.hostname,
    sshKeySecret: APP.app_settings.ssh_key_secret,
    sshKeyField: APP.app_settings.ssh_key_field,
    ingressAnnotations: {
      'cert-manager.io/cluster-issuer': APP.app_settings.cluster_issuer,
    },
    ingressClassName: 'cilium',
  },

  new(overrides):: {
    local fcObj = self,
    local config = defaults + overrides,

    // The fleet SSH key. `pi` has passwordless sudo on every node, so this credential is
    // root on the fleet -- see coordinator#261 on giving automation its own key.
    sshKey: op.item.new(config.sshKeySecret, 'vaults/' + APP.vault_name + '/items/' + config.sshKeySecret),

    // The roster. Git-authoritative like ntrip's settings.conf: edit here, merge, and the
    // hash annotation below rolls the Deployment.
    inventory:
      kConfigMap.new(std.format('%s-inventory', config.name))
      + kConfigMap.withData({ 'inventory.json': importstr 'inventory.json' }),

    // Recorded host keys. Small and rebuildable -- losing it means the next contact with
    // each node is treated as a first contact.
    statePvc:
      kPersistentVolumeClaim.new(std.format('%s-state', config.name))
      + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteOnce'])
      + kPersistentVolumeClaim.spec.resources.withRequestsMixin({ storage: '1Gi' })
      + kPersistentVolumeClaim.spec.withStorageClassName('local-path'),

    local inventoryName = fcObj.inventory.metadata.name,
    local inventoryHash = std.md5(importstr 'inventory.json'),

    deployment:
      kDeployment.new(config.name, replicas=1, containers=[
        local probe(p) =
          p.httpGet.withPath('/healthz')
          + p.httpGet.withPort(config.port.containerPort)
          + p.withPeriodSeconds(10);
        kContainer.new(config.name, config.image)
        + kContainer.withImagePullPolicy('Always')
        + kContainer.withPortsMixin([config.port])
        + kContainer.withEnvMap({
          FLEET_INVENTORY: '/config/inventory.json',
          FLEET_SSH_KEY: '/secrets/ssh/id',
          FLEET_HOSTKEYS: '/state/hostkeys.json',
        })
        + probe(kContainer.readinessProbe)
        + kContainer.readinessProbe.withInitialDelaySeconds(5)
        // No liveness probe: a bootstrap run holds state in memory for ~20 minutes, and
        // restarting the pod mid-run abandons the remaining steps (the work already on the
        // node survives, but nothing issues what comes next).
        + kContainer.resources.withRequests({ cpu: '50m', memory: '128Mi' })
        + kContainer.resources.withLimits({ memory: '256Mi' }),
      ])
      // Recreate, not RollingUpdate: two replicas could drive the same node at once, and
      // the one-action-per-node guard is per process.
      + kDeployment.spec.strategy.withType('Recreate')
      + kDeployment.mixin.spec.template.metadata.withAnnotationsMixin({
        [std.format('%s-hash', inventoryName)]: inventoryHash,
      })
      + kDeployment.spec.template.spec.withTerminationGracePeriodSeconds(30)
      // The image runs as `node` (uid/gid 1000). Secret volumes are root-owned, so a
      // 0400 key would be unreadable by the process that needs it; fsGroup makes the
      // volume group-owned by 1000 and the key group-readable.
      + kDeployment.spec.template.spec.securityContext.withFsGroup(1000)
      + k_util.configMapVolumeMount(
        fcObj.inventory,
        '/config',
        kVolumeMount.withReadOnly(true)
      )
      + k_util.secretVolumeMount(
        fcObj.sshKey.metadata.name,
        '/secrets/ssh/id',
        288,  // 0440, readable via fsGroup below
        kVolumeMount.withSubPath(config.sshKeyField) + kVolumeMount.withReadOnly(true)
      )
      + k_util.pvcVolumeMount(fcObj.statePvc.metadata.name, '/state'),

    // serviceFor names the port after the deployment (`fleet-control-http`, 18 chars) and an
    // Ingress backend port name is capped at 15. Name it `http` instead -- the length limit is
    // the constraint, not the symbol.
    local baseService = k_util.serviceFor(self.deployment),
    service: baseService {
      spec+: {
        ports: [port { name: 'http' } for port in baseService.spec.ports],
      },
    },

    ingress:
      kIngress.new(config.name)
      + kIngress.metadata.withAnnotations(config.ingressAnnotations)
      + kIngress.spec.withIngressClassName(config.ingressClassName)
      + kIngress.spec.withTls([
        kIngressTLS.withHosts([config.host])
        + kIngressTLS.withSecretName(std.format('%s-tls', config.name)),
      ])
      + kIngress.spec.withRulesMixin([
        kIngressRule.withHost(config.host)
        + kIngressRule.http.withPathsMixin(
          kHttpIngressPath.withPath('/')
          + kHttpIngressPath.withPathType('Prefix')
          + kHttpIngressPath.backend.service.withName(fcObj.service.metadata.name)
          + kHttpIngressPath.backend.service.port.withName(fcObj.service.spec.ports[0].name)
        ),
      ]),
  },
};

fleetControl.new({})
