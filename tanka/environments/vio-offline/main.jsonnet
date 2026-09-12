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
local kServiceAccount = k.core.v1.serviceAccount;

// The estimator image bakes vins_fusion_offline, the `vio-offline-runner` entrypoint, and
// COORDINATOR_SHA (its own source commit). It is multi-arch, so on this (amd64) cluster the
// pod pulls the NATIVE amd64 image -- no qemu (coordinator #85).
local image = 'ghcr.io/symmatree/coordinator-vio-estimator:main';

// The estimator config is NOT baked into the image. Fetch the deployed seed from the (public)
// coordinator repo at CONFIG_REF, so coordinator stays the single source of truth. The runner
// records the config's sha256 in the provenance sidecar, so a config change is both detectable
// and re-triggers regen (freshness keys on config sha + estimator source sha).
local configRef = 'main';
local configUrl = 'https://raw.githubusercontent.com/symmatree/coordinator/' + configRef +
                  '/host/ansible/roles/coordinator/files/oak_d.yaml';

// NFS storage: static PV binding, same pattern as flight-analysis / Mimir / Loki / ODM. Same
// NAS 'flights' subpath as flight-analysis, but a separate PV/PVC so this pipeline is
// independent (RWX -> both may mount the share concurrently).
local flightsPv =
  kPersistentVolume.new('vio-offline-flights')
  + kPersistentVolume.spec.withCapacity({ storage: '2Ti' })
  + kPersistentVolume.spec.withAccessModes(['ReadWriteMany'])
  + kPersistentVolume.spec.withPersistentVolumeReclaimPolicy('Retain')
  + kPersistentVolume.spec.nfs.withServer(APP.app_settings.nfs_server)
  + kPersistentVolume.spec.nfs.withPath(APP.app_settings.datasets_nfs_path + '/flights');

local flightsPvc =
  kPersistentVolumeClaim.new('vio-offline-flights')
  + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteMany'])
  + kPersistentVolumeClaim.spec.resources.withRequests({ storage: '2Ti' })
  + kPersistentVolumeClaim.spec.withVolumeName('vio-offline-flights')
  + kPersistentVolumeClaim.spec.withStorageClassName('');

local serviceAccount = kServiceAccount.new('vio-offline');

// initContainer: fetch the deployed config into a shared emptyDir. Uses the estimator image's
// own python3 (stdlib urllib) -- no git, no token, since coordinator is public. Fails loudly
// (non-zero -> Job fails) if the config is missing/moved rather than running on a stale copy.
local fetchConfig =
  kContainer.new('fetch-config', image)
  + kContainer.withCommand([
    'python3',
    '-c',
    "import urllib.request; "
    + "d = urllib.request.urlopen('" + configUrl + "', timeout=30).read(); "
    + "assert len(d) > 200 and b'imu:' in d, 'fetched config looks wrong'; "
    + "open('/config/oak_d.yaml', 'wb').write(d); "
    + "print('fetched oak_d.yaml', len(d), 'bytes')",
  ])
  + kContainer.resources.withRequests({ cpu: '50m', memory: '64Mi' })
  + kContainer.withVolumeMountsMixin([kVolumeMount.new('config', '/config')]);

// runner: walk /mnt/flights, regenerate <stem>.vinspose.csv + provenance sidecar for each
// *.feat, skipping fixtures already fresh. Deterministic (single-threaded, no wall-clock cap).
local runner =
  kContainer.new('runner', image)
  + kContainer.withCommand(['/opt/coordinator/bin/vio-offline-runner'])
  + kContainer.withEnvMap({
    VINS_CONFIG: '/config/oak_d.yaml',
    FLIGHTS_DIR: '/mnt/flights',
  })
  + kContainer.resources.withRequests({ cpu: '500m', memory: '1Gi' })
  + kContainer.resources.withLimits({ memory: '4Gi' })
  + kContainer.withVolumeMountsMixin([
    kVolumeMount.new('flights', '/mnt/flights'),
    kVolumeMount.new('config', '/config'),
  ]);

local volumes = [
  kVolume.fromPersistentVolumeClaim('flights', flightsPvc.metadata.name),
  kVolume.fromEmptyDir('config'),
];

local cronJob =
  kCronJob.new('vio-offline')
  // On-demand, not a nightly sweep (coordinator #139): now that the mainline compares onboard
  // VISP directly, offline regen is a leverage/gap-fill tool (config sweeps, flights missing
  // online pose), triggered manually via `kubectl create job --from=cronjob/vio-offline ...`.
  // suspend=true keeps the manifest/jobTemplate but stops the schedule; the schedule is retained
  // so re-enabling is a one-line flip if we later want gated nightly regen.
  + kCronJob.spec.withSuspend(true)
  + kCronJob.spec.withSchedule('0 5 * * *')  // retained for a future re-enable; inert while suspended
  + kCronJob.spec.withConcurrencyPolicy('Forbid')
  + kCronJob.spec.withSuccessfulJobsHistoryLimit(3)
  + kCronJob.spec.withFailedJobsHistoryLimit(3)
  + kCronJob.spec.jobTemplate.spec.template.spec.withInitContainers([fetchConfig])
  + kCronJob.spec.jobTemplate.spec.template.spec.withContainers([runner])
  + kCronJob.spec.jobTemplate.spec.template.spec.withVolumes(volumes)
  + kCronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure')
  + kCronJob.spec.jobTemplate.spec.template.spec.withServiceAccountName(serviceAccount.metadata.name);

{
  flightsPv: flightsPv,
  flightsPvc: flightsPvc,
  serviceAccount: serviceAccount,
  cronJob: cronJob,
}
