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

local odm = {

  local kPersistentVolume = k.core.v1.persistentVolume,
  local kPersistentVolumeClaim = k.core.v1.persistentVolumeClaim,
  local kDeployment = k.apps.v1.deployment,
  local kContainer = k.core.v1.container,
  local kPort = k.core.v1.containerPort,
  local kVolumeMount = k.core.v1.volumeMount,
  local kConfigMap = k.core.v1.configMap,
  local kEnvFromSource = k.core.v1.envFromSource,
  local kEnvVar = k.core.v1.envVar,
  local kIngress = k.networking.v1.ingress,
  local kIngressRule = k.networking.v1.ingressRule,
  local kHttpIngressPath = k.networking.v1.httpIngressPath,
  local kIngressBackend = k.networking.v1.ingressBackend,
  local kIngressTLS = k.networking.v1.ingressTLS,
  local kVolume = k.core.v1.volume,
  local kEmptyDirVolumeSource = k.core.v1.emptyDirVolumeSource,
  local kLifecycle = k.core.v1.lifecycle,
  local kHandler = k.core.v1.handler,
  local kExecAction = k.core.v1.execAction,
  new()::
{
local nodeOdmMemory = if APP.cluster_name == "tiles" then "6Gi" else "1Gi",
local postgresPvc = kPersistentVolumeClaim.new(name="odm-postgres")
+ kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteOnce'])
+ kPersistentVolumeClaim.spec.resources.withRequests({ storage: "10Gi" })
+ kPersistentVolumeClaim.spec.withStorageClassName('local-path'),
postgresPvc: postgresPvc,

local pgLabels = {
  app: 'odm',
  name: 'postgres',
},
local postgresInitScripts = kConfigMap.new('postgres-init-scripts')
+ kConfigMap.metadata.withLabels(pgLabels)
+ kConfigMap.withData({'init.sql': |||
  \c postgres\\
  CREATE EXTENSION IF NOT EXISTS postgis_raster CASCADE;
|||}),
postgresInitScripts: postgresInitScripts,

local postgresDeployment = kDeployment.new("postgres", containers=[
  kContainer.new('postgres', image='postgis/postgis:17-3.6-alpine')
  + kContainer.withPortsMixin([kPort.newNamed(5432, 'tcp')])
  + kContainer.withEnvMixin([
    kEnvVar.new('POSTGRES_HOST_AUTH_METHOD', 'trust'),
  ]),
], podLabels=pgLabels)
+ kDeployment.spec.template.metadata.withLabels(pgLabels)
+ k_util.pvcVolumeMount(postgresPvc.metadata.name, '/var/lib/postgresql')
+ k_util.configMapVolumeMount(postgresInitScripts, '/docker-entrypoint-initdb.d'),
postgresDeployment: postgresDeployment,

local postgresService = k_util.serviceFor(postgresDeployment),
postgresService: postgresService,

local brokerLabels = {
  app: 'odm',
  name: 'redis-broker',
},
local brokerDeployment = kDeployment.new("redis-broker", containers=[
  kContainer.new('broker', image='bitnami/redis:latest')
  + kContainer.withPortsMixin([kPort.newNamed(6379, 'tcp')])
  + kContainer.withEnvMixin([
    kEnvVar.new('ALLOW_EMPTY_PASSWORD', 'yes'),
  ]),
], podLabels=brokerLabels)
+ kDeployment.spec.template.metadata.withLabels(brokerLabels),
brokerDeployment: brokerDeployment,
local brokerService = k_util.serviceFor(brokerDeployment),
brokerService: brokerService,

// NFS storage architecture: see docs/nfs-storage-architecture.md
local datasetsPv = kPersistentVolume.new("odm-datasets")
+ kPersistentVolume.spec.withCapacity({ storage: "100Gi" })
+ kPersistentVolume.spec.withAccessModes(['ReadWriteOnce'])
+ kPersistentVolume.spec.withPersistentVolumeReclaimPolicy("Retain")
+ kPersistentVolume.spec.nfs.withServer(APP.app_settings.nfs_server)
+ kPersistentVolume.spec.nfs.withPath(APP.app_settings.datasets_nfs_path + "/webodm-media-" + APP.cluster_name),
datasetsPv: datasetsPv,

local datasetsPvc = kPersistentVolumeClaim.new("odm-datasets")
+ kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteOnce'])
+ kPersistentVolumeClaim.spec.resources.withRequests({ storage: "100Gi" })
+ kPersistentVolumeClaim.spec.withVolumeName("odm-datasets")
+ kPersistentVolumeClaim.spec.withStorageClassName(""),
datasetsPvc: datasetsPvc,

local nodeOdmLabels = {
  app: 'nodeodm',
},
local nodeOdmToleration = {
  key: 'dedicated',
  operator: 'Equal',
  value: 'nodeodm',
  effect: 'NoSchedule',
},
local nodeOdmDeployment = kDeployment.new("nodeodm", containers=[
  kContainer.new('nodeodm', image='opendronemap/nodeodm')
  + kContainer.withPortsMixin([kPort.newNamed(3000, 'tcp')])
  + kContainer.resources.withRequests({ memory: nodeOdmMemory })
  + kContainer.resources.withLimits({ memory: nodeOdmMemory })
], podLabels=nodeOdmLabels)
+ kDeployment.spec.selector.withMatchLabels(nodeOdmLabels)
+ kDeployment.spec.template.metadata.withLabels(nodeOdmLabels)
+ kDeployment.spec.template.spec.withTolerationsMixin([nodeOdmToleration])
+ kDeployment.spec.template.spec.affinity.nodeAffinity.withPreferredDuringSchedulingIgnoredDuringExecutionMixin(
  [
      {
        weight: 100,
        preference: {
          matchExpressions: [
            {
              key: 'kubernetes.io/hostname',
              operator: 'In',
              values: ['lancer'],
            },
          ],
        },
      },
    ])
+ kDeployment.emptyVolumeMount("working-dir", '/cm/local'),
nodeOdmDeployment: nodeOdmDeployment,
local nodeOdmService = k_util.serviceFor(nodeOdmDeployment),
nodeOdmService: nodeOdmService,

local redisEndpoint = brokerService.metadata.name + ':' + brokerService.spec.ports[0].port,
local webOdmPort = 8000,
local nodeOdmEndpoint = nodeOdmService.metadata.name + ':' + nodeOdmService.spec.ports[0].port,
local odmEnv = kContainer.withEnvMixin([
    kEnvVar.new('WO_BROKER', 'redis://' + redisEndpoint),
    kEnvVar.new('WO_DATABASE_HOST', postgresService.metadata.name),
    kEnvVar.new('WO_DATABASE_NAME', 'postgres'),
    kEnvVar.new('WO_DEBUG', 'no'),
    kEnvVar.new('WO_DEV', 'no'),
  ]),
local webOdmContainers = [
  kContainer.new('webodm', image='opendronemap/webodm_webapp')
  + kContainer.withPortsMixin([kPort.newNamed(webOdmPort, 'tcp')])
  + odmEnv
  + kContainer.withCommand([
    '/bin/bash',
    '-c',
    local innerCommand = "/webodm/wait-for-postgres.sh " + postgresService.metadata.name
      + " /webodm/wait-for-it.sh -t 0 " + redisEndpoint
      + " -- /webodm/start.sh";
    "chmod +x /webodm/*.sh && /bin/bash -c \"" + innerCommand + "\""])
  + kContainer.lifecycle.postStart.exec.withCommand([
        '/bin/bash',
        '-c',
        '/webodm/wait-for-it.sh -t 60 ' + nodeOdmEndpoint + ' && python manage.py addnode nodeodm 3000 || echo "Warning: Failed to register nodeodm"'
      ]),
kContainer.new('webodm-worker', image='opendronemap/webodm_webapp')
  + odmEnv
  + kContainer.withCommand([
    '/bin/bash',
    '-c',
    local innerCommand = "/webodm/wait-for-postgres.sh " + postgresService.metadata.name
      + " /webodm/wait-for-it.sh -t 0 " + redisEndpoint
      + " -- /webodm/wait-for-it.sh -t 0 webodm:" + webOdmPort
      + " -- /webodm/worker.sh start";
    "chmod +x /webodm/*.sh && /bin/bash -c \"" + innerCommand + "\""]),
],
local webOdmLabels = { app: 'webodm' },
local webOdmDeployment = kDeployment.new("webodm", containers=webOdmContainers, podLabels=webOdmLabels)
+ kDeployment.spec.selector.withMatchLabels(webOdmLabels)
+ kDeployment.spec.template.metadata.withLabels(webOdmLabels)
+ k_util.pvcVolumeMount(datasetsPvc.metadata.name, '/webodm/app/media', volumeMountMixin=kVolumeMount.withSubPath('webodm-media')),
webOdmDeployment: webOdmDeployment,
local webOdmService = k_util.serviceFor(webOdmDeployment),
webOdmService: webOdmService,

local webOdmIngress = kIngress.new("webodm")
+ kIngress.metadata.withAnnotations({
  "cert-manager.io/cluster-issuer": "real-cert"
})
+ kIngress.spec.withIngressClassName("cilium")
+ kIngress.spec.withRulesMixin([
  kIngressRule.withHost(APP.app_settings.webOdmIngressHost)
  + kIngressRule.http.withPathsMixin([
    kHttpIngressPath.withPath('/')
    + kHttpIngressPath.withPathType('Prefix')
    + kHttpIngressPath.backend.service.withName(webOdmService.metadata.name)
      + kHttpIngressPath.backend.service.port.withNumber(webOdmService.spec.ports[0].port)
  ]),
])
+ kIngress.spec.withTlsMixin([
  kIngressTLS.withHosts([APP.app_settings.webOdmIngressHost])
  + kIngressTLS.withSecretName('webodm-tls'),
]),
webOdmIngress: webOdmIngress,

}
};

odm.new()
