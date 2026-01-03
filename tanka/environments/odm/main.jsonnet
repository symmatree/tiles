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

  local kPersistentVolumeClaim = k.core.v1.persistentVolumeClaim,
  local kDeployment = k.apps.v1.deployment,
  local kContainer = k.core.v1.container,
  local kPort = k.core.v1.containerPort,
  local kVolumeMount = k.core.v1.volumeMount,
  local kConfigMap = k.core.v1.configMap,
  local kEnvFromSource = k.core.v1.envFromSource,
  local kEnvVar = k.core.v1.envVar,
  new()::
{
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
  kContainer.new('postgres', image='postgis/postgis:16-3.4')
  + kContainer.withPortsMixin([kPort.newNamed(5432, 'tcp')])
  + kContainer.withEnvMixin([
    kEnvVar.new('POSTGRES_HOST_AUTH_METHOD', 'trust'),
  ]),
], podLabels=pgLabels)
+ kDeployment.spec.template.metadata.withLabels(pgLabels)
+ k_util.pvcVolumeMount(postgresPvc.metadata.name, '/var/lib/postgresql')
+ k_util.configMapVolumeMount(postgresInitScripts, '/docker-entrypoint-initdb.d'),
postgresDeployment: postgresDeployment,

postgresService:  k_util.serviceFor(postgresDeployment)
}
};

odm.new()
