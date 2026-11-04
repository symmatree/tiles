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
local kServiceAccount = k.core.v1.serviceAccount;
local kRole = k.rbac.v1.role;
local kRoleBinding = k.rbac.v1.roleBinding;
local kPolicyRule = k.rbac.v1.policyRule;
local kSubject = k.rbac.v1.subject;

local name = 'mapping-sim';
local namespace = std.parseJson(importstr 'spec.json').spec.namespace;

// Analysis code runs in the notebook image (coordinator docs/ci.md), so render and score do too.
local notebookImage = 'ghcr.io/symmatree/tiles/datascience-notebook-ssh:main';
local odmImage = 'opendronemap/odm:3.6.2';
local coordinatorRepo = 'https://github.com/symmatree/coordinator.git';

// Every run is a directory under the datasets share's mapping-sim/: render writes images/,
// geo.txt and truth.json there, ODM uses it as its project, score writes score.json beside them.
local runsPv =
  kPersistentVolume.new('mapping-sim-runs')
  + kPersistentVolume.spec.withCapacity({ storage: '2Ti' })
  + kPersistentVolume.spec.withAccessModes(['ReadWriteMany'])
  + kPersistentVolume.spec.withPersistentVolumeReclaimPolicy('Retain')
  + kPersistentVolume.spec.nfs.withServer(APP.app_settings.nfs_server)
  + kPersistentVolume.spec.nfs.withPath(APP.app_settings.datasets_nfs_path + '/mapping-sim');

local runsPvc =
  kPersistentVolumeClaim.new('mapping-sim-runs')
  + kPersistentVolumeClaim.spec.withAccessModes(['ReadWriteMany'])
  + kPersistentVolumeClaim.spec.resources.withRequests({ storage: '2Ti' })
  + kPersistentVolumeClaim.spec.withVolumeName(runsPv.metadata.name)
  + kPersistentVolumeClaim.spec.withStorageClassName('');

// The account the workflow's pods run as: Argo's executor writes a workflowtaskresult per step.
local serviceAccount = kServiceAccount.new(name);

local workflowRole =
  kRole.new(name)
  + kRole.withRules([
    kPolicyRule.withApiGroups(['argoproj.io'])
    + kPolicyRule.withResources(['workflowtaskresults'])
    + kPolicyRule.withVerbs(['create', 'patch']),
  ]);

local workflowRoleBinding =
  kRoleBinding.new(name)
  + kRoleBinding.bindRole(workflowRole)
  + kRoleBinding.withSubjects([
    kSubject.withKind('ServiceAccount')
    + kSubject.withName(serviceAccount.metadata.name)
    + kSubject.withNamespace(namespace),
  ]);

// Clone coordinator at the requested ref into the pod and record which commit that was.
local cloneScript = |||
  set -euo pipefail
  run=/runs/{{workflow.parameters.run}}
  mkdir -p "$run"
  git clone --quiet --depth 1 --branch '{{workflow.parameters.revision}}' %s /tmp/coordinator
  sha=$(git -C /tmp/coordinator rev-parse HEAD)
||| % coordinatorRepo;

local runsMount = [{ name: 'runs', mountPath: '/runs' }];

// ODM, like the rest of the heavy work, belongs on lancer (see the odm environment).
local onLancer = {
  nodeSelector: { 'kubernetes.io/hostname': 'lancer' },
  tolerations: [{ key: 'dedicated', operator: 'Equal', value: 'heavy' }],
};

local workflowTemplate = {
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'WorkflowTemplate',
  metadata: { name: name },
  spec: {
    serviceAccountName: serviceAccount.metadata.name,
    entrypoint: 'run',
    ttlStrategy: { secondsAfterCompletion: 604800 },
    arguments: {
      parameters: [
        // Directory under mapping-sim/ on the datasets share. A rerun into an existing
        // directory overwrites its images and ODM's outputs.
        { name: 'run' },
        { name: 'config', value: 'analysis/mapping_sim/configs/as-built.yaml' },
        // A coordinator branch or tag.
        { name: 'revision', value: 'main' },
        // Extra arguments to render.py, e.g. "--scale 0.25 --limit 10".
        { name: 'render-args', value: '' },
        // Extra arguments to ODM after the fixed ones below.
        { name: 'odm-args', value: '' },
      ],
    },
    volumes: [{ name: 'runs', persistentVolumeClaim: { claimName: runsPvc.metadata.name } }],
    templates: [
      {
        name: 'run',
        steps: [
          [{ name: 'render', template: 'render' }],
          [{ name: 'odm', template: 'odm' }],
          [{ name: 'score', template: 'score' }],
        ],
      },
      {
        name: 'render',
        script: {
          image: notebookImage,
          command: ['bash'],
          source: cloneScript + |||
            echo "{\"coordinator_sha\": \"$sha\", \"config\": \"{{workflow.parameters.config}}\", \"render_args\": \"{{workflow.parameters.render-args}}\", \"odm_image\": \"%s\"}" > "$run/provenance.json"
            python3 /tmp/coordinator/analysis/mapping_sim/render.py \
              "/tmp/coordinator/{{workflow.parameters.config}}" "$run" {{workflow.parameters.render-args}}
          ||| % odmImage,
          resources: { requests: { cpu: '1', memory: '2Gi' }, limits: { memory: '4Gi' } },
          volumeMounts: runsMount,
        },
      },
      onLancer {
        name: 'odm',
        // Through bash rather than the image's entrypoint so odm-args can carry several flags.
        script: {
          image: odmImage,
          command: ['bash'],
          source: |||
            set -euo pipefail
            exec python3 /code/run.py --project-path /runs '{{workflow.parameters.run}}' \
              --geo '/runs/{{workflow.parameters.run}}/geo.txt' \
              --camera-lens fisheye_opencv --end-with opensfm --max-concurrency 16 \
              {{workflow.parameters.odm-args}}
          |||,
          resources: { requests: { cpu: '8', memory: '16Gi' }, limits: { memory: '48Gi' } },
          volumeMounts: runsMount,
        },
      },
      {
        name: 'score',
        script: {
          image: notebookImage,
          command: ['bash'],
          source: cloneScript + |||
            python3 /tmp/coordinator/analysis/mapping_sim/score.py \
              "$run" "$run/opensfm/reconstruction.json" --json "$run/score.json"
          |||,
          resources: { requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
          volumeMounts: runsMount,
        },
      },
    ],
  },
};

{
  runsPv: runsPv,
  runsPvc: runsPvc,
  serviceAccount: serviceAccount,
  workflowRole: workflowRole,
  workflowRoleBinding: workflowRoleBinding,
  workflowTemplate: workflowTemplate,
}
