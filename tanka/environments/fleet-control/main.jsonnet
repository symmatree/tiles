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
  local kRole = k.rbac.v1.role,
  local kRoleBinding = k.rbac.v1.roleBinding,
  local kPolicyRule = k.rbac.v1.policyRule,
  local kSubject = k.rbac.v1.subject,

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
    // Namespaces holding a flight artifact this service has to read. mavproxy's console log and
    // tlog; rtkbase's settings.conf and raw .ubx.
    artifactNamespaces: ['mavproxy', 'ntrip'],
    // This environment's own namespace, from spec.json. Needed explicitly because a
    // RoleBinding in ANOTHER namespace has to name where its subject lives.
    namespace: 'fleet-control',
  },

  new(overrides):: {
    local fcObj = self,
    local config = defaults + overrides,

    // ---- reading the cluster's own record of a flight -------------------------------------
    //
    // Post-flight collection needs three things this service cannot reach as shipped: the
    // mavproxy console log and its tlog, and rtkbase's settings.conf (it carries `position=`,
    // without which PPK is not possible) plus the raw .ubx. All of them live on those pods'
    // own filesystems. See coordinator#385.
    //
    // `kubectl logs` needs pods/log; `kubectl cp` is tar over exec, so it needs pods/exec and
    // pods to name the target. That is the whole list -- no secrets, no configmaps, and nothing
    // that writes to a workload.
    //
    // NOT COVERED HERE, deliberately: the backpack metrics. Those come from Mimir over HTTP at
    // mimir-gateway.mimir.svc with an X-Scope-OrgID header, which is a network path and needs
    // no Kubernetes identity at all.
    //
    // THE BLAST RADIUS IS DIFFERENT FROM WHAT THIS POD ALREADY HOLDS, which is the part worth
    // weighing rather than the size. It already mounts an ssh key that is root on every fleet
    // device; this is read access to two namespaces in the cluster. Smaller in degree, not the
    // same kind of thing.
    //
    // The grants live here rather than in the mavproxy and ntrip environments so that "what
    // fleet-control may do" is one file to read. That is the opposite of the usual
    // namespace-owner-grants direction, and it is a deliberate trade for reviewability.

    serviceAccount: kServiceAccount.new(config.name),

    local readPods = [
      kPolicyRule.withApiGroups([''])
      + kPolicyRule.withResources(['pods'])
      + kPolicyRule.withVerbs(['get', 'list']),
      kPolicyRule.withApiGroups([''])
      + kPolicyRule.withResources(['pods/log'])
      + kPolicyRule.withVerbs(['get']),
      kPolicyRule.withApiGroups([''])
      + kPolicyRule.withResources(['pods/exec'])
      + kPolicyRule.withVerbs(['create']),
    ],

    local grantIn(ns) = {
      role:
        kRole.new(std.format('%s-reader', config.name))
        + kRole.metadata.withNamespace(ns)
        + kRole.withRules(readPods),
      binding:
        kRoleBinding.new(std.format('%s-reader', config.name))
        + kRoleBinding.metadata.withNamespace(ns)
        + kRoleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
        + kRoleBinding.roleRef.withKind('Role')
        + kRoleBinding.roleRef.withName(std.format('%s-reader', config.name))
        + kRoleBinding.withSubjects([
          kSubject.withKind('ServiceAccount')
          + kSubject.withName(config.name)
          + { namespace: config.namespace },
        ]),
    },

    // One pair per namespace holding an artifact a flight needs.
    artifactReaders: {
      [ns]: grantIn(ns)
      for ns in config.artifactNamespaces
    },

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
      + k_util.pvcVolumeMount(fcObj.flightsPvc.metadata.name, '/mnt/flights'),

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
