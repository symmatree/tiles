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
  local kEnvVar = k.core.v1.envVar,
  local kPersistentVolumeClaim = k.core.v1.persistentVolumeClaim,
  local kPersistentVolume = k.core.v1.persistentVolume,
  local kIngress = k.networking.v1.ingress,
  local kIngressRule = k.networking.v1.ingressRule,
  local kHttpIngressPath = k.networking.v1.httpIngressPath,
  local kIngressTLS = k.networking.v1.ingressTLS,
  local kServiceAccount = k.core.v1.serviceAccount,

  local defaults = {
    name: 'fleet-control',
    image: APP.app_settings.image,
    port: kPort.newNamed(8080, 'http'),
    host: APP.app_settings.hostname,
    sshKeySecret: APP.app_settings.ssh_key_secret,
    sshKeyField: APP.app_settings.ssh_key_field,
    githubTokenSecret: APP.app_settings.github_token_secret,
    githubTokenField: APP.app_settings.github_token_field,
    ingressAnnotations: {
      'cert-manager.io/cluster-issuer': APP.app_settings.cluster_issuer,
    },
    ingressClassName: 'cilium',
    // Where the pod bus is. The coordinator runs the broker, and the roster already says where
    // the coordinator is, so this reads it from there. `host` is optional in the roster and
    // defaults to the node name, which is also a usable address.
    local roster = std.parseJson(importstr 'inventory.json'),
    local coordinator = std.filter(function(n) n.role == 'coordinator', roster.nodes),
    brokerHost: if std.length(coordinator) == 1
    then std.get(coordinator[0], 'host', coordinator[0].name)
    else error 'the roster must name exactly one coordinator, for the broker address',
  },

  new(overrides):: {
    local fcObj = self,
    local config = defaults + overrides,

    // ---- what this service may do in the cluster -------------------------------------------
    //
    // NOTHING. It has a ServiceAccount because a pod has one, and no Role anywhere.
    //
    // It used to hold pods get/list, pods/log and pods/exec in `mavproxy` and `ntrip`, to read
    // mavproxy's console log and tlog and rtkbase's settings.conf and raw .ubx. Every one of
    // those reads is gone: the console log is cluster debugging output rather than flight data,
    // settings.conf is git-authoritative in this repo so it already has a history, the tlogs come
    // off a share tlog-split writes to, and the raw observations now come off a share rtkbase
    // writes to (coordinator#414, coordinator#416).
    //
    // Which is the better shape anyway. Reading a few hundred megabytes of GNSS observations
    // through `kubectl exec ... cat` never worked -- it buffered into 64 MB -- and the fix for
    // that was not a bigger buffer.

    serviceAccount: kServiceAccount.new(config.name),

    // The fleet SSH key. `pi` has passwordless sudo on every node, so this credential is
    // root on the fleet -- see coordinator#261 on giving automation its own key.
    sshKey: op.item.new(config.sshKeySecret, 'vaults/' + APP.vault_name + '/items/' + config.sshKeySecret),

    // Read-only access to Actions artifacts. Not root on anything, unlike the ssh key --
    // it can fetch published build artifacts and nothing else.
    //
    // The 1Password title is FLEET_GITHUB_TOKEN, which is not a legal Kubernetes object name
    // -- those are DNS-1123, so lowercase with no underscores. The item path keeps the title
    // and the object gets a derived name; the Secret the operator creates takes that name,
    // which is what the env var below references.
    local k8sName(title) = std.strReplace(std.asciiLower(title), '_', '-'),
    githubToken: op.item.new(
      k8sName(config.githubTokenSecret),
      'vaults/' + APP.vault_name + '/items/' + config.githubTokenSecret
    ),

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

    // Where recovered flights land. A static PV because `datasets` is a different NFS
    // export from the one cluster-nfs provisions into -- same server, /volume2/datasets
    // rather than /volume2/tiles -- so a dynamic claim cannot reach it. Same pattern and
    // the same subpath as flight-analysis and vio-offline; a separate PV/PVC of our own so
    // the three mount it independently (RWX).
    //
    // Retain, not Delete: this holds the only copy of a flight once the device is wiped.
    flightsPv:
      kPersistentVolume.new(std.format('%s-flights', config.name))
      + kPersistentVolume.spec.withCapacity({ storage: '2Ti' })
      + kPersistentVolume.spec.withAccessModes(['ReadWriteMany'])
      + kPersistentVolume.spec.withPersistentVolumeReclaimPolicy('Retain')
      + kPersistentVolume.spec.nfs.withServer(APP.app_settings.nfs_server)
      + kPersistentVolume.spec.nfs.withPath(APP.app_settings.datasets_nfs_path + '/flights'),

    flightsPvc:
      kPersistentVolumeClaim.new(std.format('%s-flights', config.name))
      + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteMany'])
      + kPersistentVolumeClaim.spec.resources.withRequests({ storage: '2Ti' })
      + kPersistentVolumeClaim.spec.withVolumeName(std.format('%s-flights', config.name))
      + kPersistentVolumeClaim.spec.withStorageClassName(''),

    // The per-flight tlogs tlog-split writes (containers/tlog-split, in the mavproxy env).
    // READ-ONLY: this service picks the one matching a flight's armed window and copies it into
    // the flight directory. tlog-split owns writing them.
    tlogsPv:
      kPersistentVolume.new(std.format('%s-ground-tlogs', config.name))
      + kPersistentVolume.spec.withCapacity({ storage: '200Gi' })
      + kPersistentVolume.spec.withAccessModes(['ReadWriteMany'])
      + kPersistentVolume.spec.withPersistentVolumeReclaimPolicy('Retain')
      + kPersistentVolume.spec.nfs.withServer(APP.app_settings.nfs_server)
      + kPersistentVolume.spec.nfs.withPath(APP.app_settings.datasets_nfs_path + '/ground-tlogs'),

    tlogsPvc:
      kPersistentVolumeClaim.new(std.format('%s-ground-tlogs', config.name))
      + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteMany'])
      + kPersistentVolumeClaim.spec.resources.withRequests({ storage: '200Gi' })
      + kPersistentVolumeClaim.spec.withVolumeName(std.format('%s-ground-tlogs', config.name))
      + kPersistentVolumeClaim.spec.withStorageClassName(''),

    // Disk images the service has pushed. Nothing evicts them; the point is that pushing one
    // image to five machines is one fetch and five local reads (coordinator#312).
    //
    // cluster-nfs rather than local-path: local-path is node-local, so the cache would pin
    // this pod to one node and die with it. Read speed is not a tiebreaker -- a device pulls
    // at roughly 0.9 MB/s, far below anything the NAS does. 20 Gi is about 24 images at the
    // current 813 MiB, with nothing evicting.
    imagePvc:
      kPersistentVolumeClaim.new(std.format('%s-images', config.name))
      + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteOnce'])
      + kPersistentVolumeClaim.spec.resources.withRequestsMixin({ storage: '20Gi' })
      + kPersistentVolumeClaim.spec.withStorageClassName('cluster-nfs'),

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
          // The name the service actually reads, and the reason the PVC below exists:
          // recorded host keys must land on /state to survive a pod restart.
          FLEET_KNOWN_HOSTS: '/state/known_hosts',
          FLEET_IMAGE_CACHE: '/images',
          // The PLATFORM level, not the flights root. flight-data-layout.md is
          // `flights/<platform>/<flight>/`, and the service joins only the flight name it
          // is given -- so pointed at the root it writes a sibling of `rekon10/` rather
          // than into it. The 2026-09-23 capture landed at `flights/260923-test-mission/`
          // and had to be moved by hand.
          //
          // One platform is hardcoded because there is one fleet: every node in
          // inventory.json is a rekon10. The share also holds `firefly16/`, so if a second
          // platform ever has devices in the roster this becomes per-node rather than
          // per-service.
          FLEET_FLIGHTS_DIR: '/mnt/flights/rekon10',
          // A campod converge is twenty minutes or more, so the run's ending has to reach the
          // operator rather than waiting in a browser tab. The service also announces its own
          // start, because a restart ENDS any run in flight -- the registry is in memory and the
          // playbook is a child of the process.
          //
          // In-cluster, so no ingress and no TLS in the path. `apprise` is the config key; the
          // tag is required, since an untagged notify matches zero targets.
          FLEET_NOTIFY_URL: 'http://apprise.apprise.svc:8000/notify/apprise',
          FLEET_NOTIFY_TAG: APP.cluster_name,
          FLEET_GROUND_TLOGS: '/mnt/ground-tlogs',
          // The pod bus (coordinator#450). The broker is mochi-mqtt on the coordinator itself,
          // not a cluster service, so this is the coordinator's own address -- taken from the
          // roster below rather than written again here, because the same address in two places
          // is one of them being wrong later.
          FLEET_MQTT_URL: 'mqtt://' + config.brokerHost + ':1883',
          // Where a DEVICE reaches this service: it fetches its own image with get_url, so
          // the in-cluster service name is no use to it.
          FLEET_PUBLIC_URL: 'https://' + config.host,
        })
        + kContainer.withEnvMixin([
          kEnvVar.withName('FLEET_GITHUB_TOKEN')
          + kEnvVar.valueFrom.secretKeyRef.withName(fcObj.githubToken.metadata.name)
          + kEnvVar.valueFrom.secretKeyRef.withKey(config.githubTokenField),
        ])
        + probe(kContainer.readinessProbe)
        + kContainer.readinessProbe.withInitialDelaySeconds(5)
        // No liveness probe: a converge holds state in memory for 20 minutes or more, and
        // restarting the pod mid-run abandons the remaining steps (the work already on the
        // node survives, but nothing issues what comes next).
        + kContainer.resources.withRequests({ cpu: '50m', memory: '128Mi' })
        + kContainer.resources.withLimits({ memory: '256Mi' }),
      ])
      // Recreate, not RollingUpdate: two replicas could drive the same node at once, and
      // the one-action-per-node guard is per process.
      + kDeployment.spec.template.spec.withServiceAccountName(fcObj.serviceAccount.metadata.name)
      + kDeployment.spec.strategy.withType('Recreate')
      // Opts this Deployment in to argo-tag-watcher's image side: the image is a
      // floating :main tag, so a rebuild moves the digest without changing the
      // string here and nothing would otherwise roll the pod. The playbook is baked
      // into the image, so a stale pod runs a playbook that is not the one in main.
      // See containers/argo-tag-watcher/README.md. Restarting abandons a converge
      // that happens to be running; a converge is re-runnable by design.
      + kDeployment.metadata.withAnnotationsMixin({
        'tiles.symmatree.com/roll-on-digest-change': 'true',
      })
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
      + k_util.pvcVolumeMount(fcObj.statePvc.metadata.name, '/state')
      + k_util.pvcVolumeMount(fcObj.imagePvc.metadata.name, '/images')
      + k_util.pvcVolumeMount(fcObj.flightsPvc.metadata.name, '/mnt/flights')
      + k_util.pvcVolumeMount(fcObj.tlogsPvc.metadata.name, '/mnt/ground-tlogs'),

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
