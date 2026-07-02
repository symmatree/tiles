local k = import 'k.libsonnet';

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

local kPersistentVolume = k.core.v1.persistentVolume;
local kPersistentVolumeClaim = k.core.v1.persistentVolumeClaim;
local kCronJob = k.batch.v1.cronJob;
local kContainer = k.core.v1.container;
local kVolumeMount = k.core.v1.volumeMount;
local kVolume = k.core.v1.volume;
local kConfigMap = k.core.v1.configMap;
local kServiceAccount = k.core.v1.serviceAccount;

// NFS storage: static PV binding (same pattern as Mimir/Loki/ODM).
// The 'datasets' share is NAS-owned; we bind to a specific subpath.
local flightsPv =
  kPersistentVolume.new('flight-analysis-flights')
  + kPersistentVolume.spec.withCapacity({ storage: '2Ti' })
  + kPersistentVolume.spec.withAccessModes(['ReadWriteMany'])
  + kPersistentVolume.spec.withPersistentVolumeReclaimPolicy('Retain')
  + kPersistentVolume.spec.nfs.withServer(APP.app_settings.nfs_server)
  + kPersistentVolume.spec.nfs.withPath(APP.app_settings.datasets_nfs_path + '/flights');

local flightsPvc =
  kPersistentVolumeClaim.new('flight-analysis-flights')
  + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteMany'])
  + kPersistentVolumeClaim.spec.resources.withRequests({ storage: '2Ti' })
  + kPersistentVolumeClaim.spec.withVolumeName('flight-analysis-flights')
  + kPersistentVolumeClaim.spec.withStorageClassName('');

local runnerConfigMap =
  kConfigMap.new('flight-analysis-runner')
  + kConfigMap.withData({ 'runner.py': importstr 'runner.py' });

local serviceAccount = kServiceAccount.new('flight-analysis');

local container =
  kContainer.new('runner', image='ghcr.io/symmatree/tiles/datascience-notebook-ssh:main')
  + kContainer.withCommand(['python', '/runner/runner.py'])
  + kContainer.resources.withRequests({ cpu: '500m', memory: '2Gi' })
  + kContainer.resources.withLimits({ memory: '4Gi' })
  + kContainer.withVolumeMountsMixin([
    kVolumeMount.new('flights', '/mnt/flights'),
    kVolumeMount.new('runner-script', '/runner'),
    kVolumeMount.new('workspace', '/workspace'),
  ]);

local volumes = [
  kVolume.fromPersistentVolumeClaim('flights', flightsPvc.metadata.name),
  kVolume.fromConfigMap('runner-script', runnerConfigMap.metadata.name),
  kVolume.fromEmptyDir('workspace'),
];

local cronJob =
  kCronJob.new('flight-analysis')
  + kCronJob.spec.withSchedule('0 4 * * *')
  + kCronJob.spec.withConcurrencyPolicy('Forbid')
  + kCronJob.spec.withSuccessfulJobsHistoryLimit(3)
  + kCronJob.spec.withFailedJobsHistoryLimit(3)
  + kCronJob.spec.jobTemplate.spec.template.spec.withContainers([container])
  + kCronJob.spec.jobTemplate.spec.template.spec.withVolumes(volumes)
  + kCronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure')
  + kCronJob.spec.jobTemplate.spec.template.spec.withServiceAccountName(serviceAccount.metadata.name);

{
  flightsPv: flightsPv,
  flightsPvc: flightsPvc,
  runnerConfigMap: runnerConfigMap,
  serviceAccount: serviceAccount,
  cronJob: cronJob,
}
