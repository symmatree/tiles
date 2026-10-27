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
    // Where the pod bus is. The coordinator runs the broker, and the roster already says where
    // the coordinator is, so this reads it from there. `host` is optional in the roster and
    // defaults to the node name, which is also a usable address.
    local roster = std.parseJson(importstr 'inventory.json'),
    // Tanka stamps this onto every object at manifestation, but a RoleBinding subject has
    // to carry it explicitly.
    namespace: std.parseJson(importstr 'spec.json').spec.namespace,
    local coordinator = std.filter(function(n) n.role == 'coordinator', roster.nodes),
    sshUser: roster.user,
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

    // ---- running a converge as an Argo Workflow (coordinator#504) ---------------------
    // Design and reasoning are in README.md.

    // The account the workflow's own PODS run as. Argo's executor writes a
    // workflowtaskresult per step, which is all this needs to be able to do.
    workflowServiceAccount: kServiceAccount.new(std.format('%s-workflow', config.name)),

    workflowRole:
      kRole.new(std.format('%s-workflow', config.name))
      + kRole.withRules([
        kPolicyRule.withApiGroups(['argoproj.io'])
        + kPolicyRule.withResources(['workflowtaskresults'])
        + kPolicyRule.withVerbs(['create', 'patch']),
      ]),

    workflowRoleBinding:
      kRoleBinding.new(std.format('%s-workflow', config.name))
      + kRoleBinding.bindRole(self.workflowRole)
      + kRoleBinding.withSubjects([
        kSubject.withKind('ServiceAccount')
        + kSubject.withName(self.workflowServiceAccount.metadata.name)
        + kSubject.withNamespace(config.namespace),
      ]),

    // What the SERVICE may do: submit a converge, find it again, read a running step's log.
    submitRole:
      kRole.new(std.format('%s-submit', config.name))
      + kRole.withRules([
        kPolicyRule.withApiGroups(['argoproj.io'])
        + kPolicyRule.withResources(['workflows'])
        + kPolicyRule.withVerbs(['create', 'get', 'list', 'watch', 'delete']),
        kPolicyRule.withApiGroups([''])
        + kPolicyRule.withResources(['pods', 'pods/log'])
        + kPolicyRule.withVerbs(['get', 'list', 'watch']),
      ]),

    submitRoleBinding:
      kRoleBinding.new(std.format('%s-submit', config.name))
      + kRoleBinding.bindRole(self.submitRole)
      + kRoleBinding.withSubjects([
        kSubject.withKind('ServiceAccount')
        + kSubject.withName(self.serviceAccount.metadata.name)
        + kSubject.withNamespace(config.namespace),
      ]),

    // The exit handler every service-submitted workflow runs: say how it ended
    // (coordinator#566). The service holds no record of a run, so the workflow announces
    // its own ending, from a step that exists whether or not the service's pod does. The
    // body is `notify-step.js` out of the service's image, so it versions with it; a
    // notify that fails cannot fail the workflow (the step never exits non-zero on it).
    //
    // `subject` is what the notification is about: the node for a playbook run, the flight
    // for a collect. The action comes off the label the service set at submit.
    local notifyTemplate(subject) = {
      name: 'notify',
      container: {
        image: config.image,
        // Always, for the reason every step here gives: `:main` floats and a workflow
        // pod has no tag watcher.
        imagePullPolicy: 'Always',
        command: [
          'node',
          '/app/dist/notify-step.js',
          '{{workflow.name}}',
          '{{workflow.labels.fleet-control.symmatree.com/action}}',
          subject,
          '{{workflow.status}}',
          '{{workflow.failures}}',
        ],
        env: [
          { name: 'FLEET_NOTIFY_URL', value: 'http://apprise.apprise.svc:8000/notify/apprise' },
          { name: 'FLEET_NOTIFY_TAG', value: APP.cluster_name },
        ],
        resources: {
          requests: { cpu: '20m', memory: '48Mi' },
          limits: { memory: '128Mi' },
        },
      },
    },

    // What the service submits a playbook run against: converge, full provision, reimage.
    // See README.md.
    playbookTemplate: {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'WorkflowTemplate',
      metadata: { name: std.format('%s-playbook', config.name) },
      spec: {
        serviceAccountName: fcObj.workflowServiceAccount.metadata.name,
        entrypoint: 'run',
        onExit: 'notify',

        // No activeDeadlineSeconds, and the TTL is how far back the run record reaches.
        // Both are explained in README.md.
        ttlStrategy: { secondsAfterCompletion: 604800 },

        arguments: {
          parameters: [
            { name: 'playbook' },
            { name: 'host' },
            { name: 'device-role' },
            { name: 'artifact-url' },
            { name: 'revision' },
            // A JSON object, merged into what the play is given. Default empty: a converge
            // needs none, reimage needs two. The step refuses any that would displace the
            // vars it sets itself.
            { name: 'extra-vars', value: '{}' },
          ],
        },

        templates: [{
          name: 'run',
          inputs: {
            parameters: [
              { name: 'playbook' },
              { name: 'host' },
              { name: 'device-role' },
              { name: 'artifact-url' },
              { name: 'revision' },
              { name: 'extra-vars', value: '{}' },
            ],
          },
          // 0440 and group 1000, matching the key's mode below, as in the Deployment.
          securityContext: { fsGroup: 1000 },
          volumes: [{
            name: 'ssh-key',
            secret: {
              secretName: fcObj.sshKey.metadata.name,
              defaultMode: 288,  // 0440
            },
          }],
          container: {
            image: config.image,
            command: [
              '/usr/local/bin/run-playbook.sh',
              '{{inputs.parameters.playbook}}',
              '{{inputs.parameters.host}}',
              '{{inputs.parameters.device-role}}',
            ],
            volumeMounts: [{
              name: 'ssh-key',
              mountPath: '/secrets/ssh/id',
              subPath: config.sshKeyField,
              readOnly: true,
            }],
            env: [
              { name: 'FLEET_SSH_KEY', value: '/secrets/ssh/id' },
              // The public half, a second field of the same item.
              {
                name: 'FLEET_SSH_PUBLIC_KEY',
                valueFrom: {
                  secretKeyRef: {
                    name: fcObj.sshKey.metadata.name,
                    key: 'public-key',
                  },
                },
              },
              {
                name: 'FLEET_GITHUB_TOKEN',
                valueFrom: {
                  secretKeyRef: {
                    name: fcObj.githubToken.metadata.name,
                    key: config.githubTokenField,
                  },
                },
              },
              // From the roster, the same file the service reads it from.
              { name: 'FLEET_SSH_USER', value: config.sshUser },
              { name: 'PLAYBOOK_ARTIFACT_URL', value: '{{inputs.parameters.artifact-url}}' },
              { name: 'PLAYBOOK_REVISION', value: '{{inputs.parameters.revision}}' },
              { name: 'PLAYBOOK_EXTRA_VARS', value: '{{inputs.parameters.extra-vars}}' },
            ],
            // One ansible interpreter measures about 60 MB.
            resources: {
              requests: { cpu: '50m', memory: '128Mi' },
              limits: { memory: '512Mi' },
            },
          },
        }, notifyTemplate('{{workflow.labels.fleet-control.symmatree.com/node}}')],
      },
    },

    // The bench simulated-flight cycle (coordinator#541). Design and reasoning are in
    // README.md. The stages are `bench-cycle` in the same image, so they version with it.
    benchTemplate: {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'WorkflowTemplate',
      metadata: { name: 'bench-simflight' },
      spec: {
        serviceAccountName: fcObj.workflowServiceAccount.metadata.name,
        entrypoint: 'cycle',
        onExit: 'disarm',
        ttlStrategy: { secondsAfterCompletion: 604800 },
        // Unlike the playbook template, which deliberately has none: this one holds the rig
        // armed, and a cycle that hangs somewhere holds it armed indefinitely. Generous
        // enough for two converges, three reboots and the window.
        activeDeadlineSeconds: 5400,

        arguments: {
          parameters: [
            { name: 'flight' },
            { name: 'window-seconds', value: '240' },
          ],
        },

        templates: [
          {
            name: 'cycle',
            steps: [
              [{ name: 'deploy', template: 'stage', arguments: { parameters: [{ name: 'stage', value: 'deploy' }] } }],
              [{ name: 'arm', template: 'stage', arguments: { parameters: [{ name: 'stage', value: 'arm' }] } }],
              [{ name: 'window', template: 'window' }],
              [{ name: 'disarm', template: 'stage', arguments: { parameters: [{ name: 'stage', value: 'disarm' }] } }],
              [{ name: 'collect', template: 'stage', arguments: { parameters: [{ name: 'stage', value: 'collect' }] } }],
            ],
          },

          // The measurement window. A suspended step has no pod, so nothing of ours is
          // scheduled, logging or polling on a 417 MiB board while the cameras are timed.
          {
            name: 'window',
            suspend: { duration: '{{workflow.parameters.window-seconds}}' },
          },

          // Runs on exit whatever happened, so a cycle that fails or is stopped mid-window
          // does not leave the rig armed with the FC talker stopped. Writing 0 twice is
          // what the device already expects.
          {
            name: 'disarm',
            steps: [
              [{
                name: 'disarm',
                template: 'stage',
                arguments: { parameters: [{ name: 'stage', value: 'disarm' }] },
              }],
            ],
          },

          {
            name: 'stage',
            inputs: { parameters: [{ name: 'stage' }] },
            // No retryStrategy, on purpose: a failed converge or a missed `ready` means the
            // fleet is not in the state the trial assumes, and retrying against a device
            // mid-reboot produces a trial whose conditions nobody knows.
            securityContext: { fsGroup: 1000 },
            volumes: [{
              name: 'ssh-key',
              secret: {
                secretName: fcObj.sshKey.metadata.name,
                defaultMode: 288,  // 0440
              },
            }],
            container: {
              image: config.image,
              // ALWAYS, because the tag floats. `:main` is not `:latest`, so Kubernetes
              // defaults it to IfNotPresent: on 2026-10-18 all three steps ran on
              // tiles-wk-3, whose cached `:main` predated the fix they were testing, and
              // the kubelet said so -- "already present on machine". The Deployment does
              // not have this problem because the tag watcher rolls it on digest change,
              // which pulls; a workflow pod has no such trigger.
              imagePullPolicy: 'Always',
              command: [
                '/usr/local/bin/bench-cycle',
                '{{inputs.parameters.stage}}',
                '--flight',
                '{{workflow.parameters.flight}}',
              ],
              volumeMounts: [{
                name: 'ssh-key',
                mountPath: '/secrets/ssh/id',
                subPath: config.sshKeyField,
                readOnly: true,
              }],
              env: [
                // The service's own address in this namespace, not the ingress: a step has
                // no reason to leave the cluster to reach it.
                {
                  name: 'FLEET_URL',
                  value: std.format('http://%s:%d', [config.name, config.port.containerPort]),
                },
                { name: 'FLEET_SSH_KEY', value: '/secrets/ssh/id' },
                { name: 'FLEET_SSH_USER', value: config.sshUser },
              ],
              resources: {
                requests: { cpu: '50m', memory: '64Mi' },
                limits: { memory: '256Mi' },
              },
            },
          },
        ],
      },
    },

    // Collecting a flight: one step per thing retrieved, and nothing after them.
    // coordinator#566, and the reasoning is in README.md.
    //
    // The service used to move these bytes itself, which made every retrieval serial and
    // tied it to that pod's lifetime -- 336 and 361 MB landing seven minutes apart on
    // 2026-10-18, with an FC log that takes about 30 minutes for 148 MB queued behind them
    // for no reason, since it is a different device. Here they all start together, except
    // two of one kind on one device, which take turns -- see the step's `synchronization`.
    //
    // ONE STEP TEMPLATE FOR BOTH KINDS. A target is `{node, kind, id}` whatever it is, so
    // the fan-out spreads sessions and FC logs into the same shape and there is no second
    // template to keep in step with the first.
    //
    // NO JOIN. Each step writes its own file under the flight's `collected/`, so there is
    // no manifest to merge and nothing for a final step to reconcile. The reader globs the
    // directory.
    collectTemplate: {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'WorkflowTemplate',
      metadata: { name: std.format('%s-collect', config.name) },
      spec: {
        serviceAccountName: fcObj.workflowServiceAccount.metadata.name,
        entrypoint: 'collect',
        onExit: 'notify',
        // As for the playbook template: no activeDeadlineSeconds, and the TTL is how far
        // back the record reaches. A transfer is slow by nature, and a deadline would fail
        // the long ones -- which are the ones carrying the most data.
        ttlStrategy: { secondsAfterCompletion: 604800 },

        arguments: {
          parameters: [
            { name: 'flight' },
            // `[{"node": ..., "session": ...}, ...]`. The fan-out spreads this, so another
            // campod is a longer list and nothing else.
            { name: 'targets' },
          ],
        },

        volumes: [
          {
            name: 'ssh-key',
            secret: { secretName: fcObj.sshKey.metadata.name, defaultMode: 288 },  // 0440
          },
          // The datasets share. RWX, which is what lets two step pods on different nodes
          // write into one flight directory at the same time.
          {
            name: 'flights',
            persistentVolumeClaim: { claimName: fcObj.flightsPvc.metadata.name },
          },
          { name: 'inventory', configMap: { name: fcObj.inventory.metadata.name } },
        ],

        local mounts = [
          { name: 'flights', mountPath: '/mnt/flights' },
          { name: 'inventory', mountPath: '/config', readOnly: true },
        ],
        // The same env the Deployment gives the service, because a step runs the service's
        // own code: it reads the roster, reaches a device over ssh, and quiesces it over
        // the pod bus before touching it.
        local stepEnv = [
          { name: 'FLEET_INVENTORY', value: '/config/inventory.json' },
          { name: 'FLEET_FLIGHTS_DIR', value: '/mnt/flights/rekon10' },
          { name: 'FLEET_MQTT_URL', value: 'mqtt://' + config.brokerHost + ':1883' },
          { name: 'FLEET_SSH_KEY', value: '/secrets/ssh/id' },
          { name: 'FLEET_SSH_USER', value: config.sshUser },
        ],

        templates: [
          {
            name: 'collect',
            inputs: { parameters: [{ name: 'flight' }, { name: 'targets' }] },
            dag: {
              tasks: [
                {
                  name: 'offload',
                  template: 'offload',
                  withParam: '{{inputs.parameters.targets}}',
                  arguments: {
                    parameters: [
                      { name: 'node', value: '{{item.node}}' },
                      { name: 'kind', value: '{{item.kind}}' },
                      { name: 'id', value: '{{item.id}}' },
                    ],
                  },
                },
              ],
            },
          },
          {
            name: 'offload',
            inputs: { parameters: [{ name: 'node' }, { name: 'kind' }, { name: 'id' }] },
            // ONE AT A TIME PER DEVICE AND KIND. An FC log is pulled over the coordinator's
            // one UART, and two readers on it each get part of the byte stream: on
            // 2026-10-25 three fc-log steps started together and two died with pyserial's
            // "device reports readiness to read but returned no data". Keyed on kind as well
            // as node so a coordinator session (15 s) does not queue behind a 25-minute log;
            // that cost two sessions on one node taking turns. Mutexes are namespace-wide, so
            // this also holds across two collect workflows.
            synchronization: {
              mutexes: [{ name: 'collect-{{inputs.parameters.node}}-{{inputs.parameters.kind}}' }],
            },
            // 0440 and group 1000, matching the key's mode, as in the Deployment.
            securityContext: { fsGroup: 1000 },
            container: {
              image: config.image,
              // ALWAYS, for the reason the bench template gives: `:main` floats, and a
              // workflow pod has no tag watcher to roll it, so a cached layer wins silently.
              imagePullPolicy: 'Always',
              command: [
                'node',
                '/app/dist/offload-step.js',
                '{{inputs.parameters.node}}',
                '{{inputs.parameters.kind}}',
                '{{inputs.parameters.id}}',
                '{{workflow.parameters.flight}}',
              ],
              volumeMounts: mounts + [{
                name: 'ssh-key',
                mountPath: '/secrets/ssh/id',
                subPath: config.sshKeyField,
                readOnly: true,
              }],
              env: stepEnv,
              // The transfer is streamed to disk and hashed in the same pass, so what this
              // holds is a few buffers rather than the bundle: 361 MB moved by a process
              // that never has it.
              resources: {
                requests: { cpu: '100m', memory: '96Mi' },
                limits: { memory: '384Mi' },
              },
            },
          },
          notifyTemplate('{{workflow.parameters.flight}}'),
        ],
      },
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
