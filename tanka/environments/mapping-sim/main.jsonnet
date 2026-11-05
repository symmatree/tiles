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

// The datasets share's mapping-sim/, mounted at /data. renders/<render>/ is a rendered capture,
// written once (images/, geo.txt, truth.json, manifest.json, README.md); runs/<run>/ is one
// processing of a render: ODM's project, run.json and score.json.
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

local dataMount = { name: 'data', mountPath: '/data' };

// Clone coordinator at the requested ref into the pod and record which commit that was.
local cloneScript = |||
  set -euo pipefail
  git clone --quiet --depth 1 --branch '{{inputs.parameters.revision}}' %s /tmp/coordinator
  sha=$(git -C /tmp/coordinator rev-parse HEAD)
||| % coordinatorRepo;

// Rendering and ODM, like the rest of the heavy work, belong on lancer (see the odm environment).
local onLancer = {
  nodeSelector: { 'kubernetes.io/hostname': 'lancer' },
  tolerations: [{ key: 'dedicated', operator: 'Equal', value: 'heavy' }],
};

local inputs(names) = { inputs: { parameters: [{ name: n } for n in names] } };

// Writes renders/<render>/ and fails if it already exists: a render is kept as written, since any
// number of runs may read it. render.py writes its own manifest.json and README.md.
local renderTemplate = onLancer + inputs(['render', 'config', 'revision', 'render-args']) {
  name: 'render',
  script: {
    image: notebookImage,
    command: ['bash'],
    // 16 single-threaded render processes, about 430 MB each at full resolution;
    // render-args comes after --jobs so it can override it.
    env: [{ name: 'OMP_NUM_THREADS', value: '1' }, { name: 'OPENBLAS_NUM_THREADS', value: '1' }],
    source: cloneScript + |||
      mkdir -p /data/renders
      mkdir '/data/renders/{{inputs.parameters.render}}'
      cd /tmp/coordinator
      python3 analysis/mapping_sim/render.py '{{inputs.parameters.config}}' \
        '/data/renders/{{inputs.parameters.render}}' --jobs 16 {{inputs.parameters.render-args}}
    |||,
    resources: { requests: { cpu: '16', memory: '10Gi' }, limits: { memory: '16Gi' } },
    volumeMounts: [dataMount],
  },
};

// ODM's project is runs/<run>/, with the render's images/ mounted into it read-only so that no
// run can change a render, and the render's geo.txt as the priors. run.json records what ran.
local odmTemplate = onLancer + inputs(['run', 'render', 'odm-args']) {
  name: 'odm',
  // Through bash rather than the image's entrypoint so odm-args can carry several flags.
  script: {
    image: odmImage,
    command: ['bash'],
    source: |||
      set -euo pipefail
      render='/data/renders/{{inputs.parameters.render}}'
      run='/data/runs/{{inputs.parameters.run}}'
      python3 - "$render" "$run" <<'EOF'
      import datetime, hashlib, json, pathlib, sys
      render, run = map(pathlib.Path, sys.argv[1:])
      (run / "run.json").write_text(json.dumps({
          "render": "{{inputs.parameters.render}}",
          "render_manifest_sha256": hashlib.sha256((render / "manifest.json").read_bytes()).hexdigest(),
          "odm_image": "%s",
          "odm_args": "{{inputs.parameters.odm-args}}",
          "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
      }, indent=1))
      EOF
      exec python3 /code/run.py --project-path /data/runs '{{inputs.parameters.run}}' \
        --geo "$render/geo.txt" \
        --camera-lens fisheye_opencv --end-with opensfm --max-concurrency 16 \
        {{inputs.parameters.odm-args}}
    ||| % odmImage,
    resources: { requests: { cpu: '8', memory: '16Gi' }, limits: { memory: '48Gi' } },
    volumeMounts: [
      dataMount,
      {
        name: 'data',
        subPath: 'renders/{{inputs.parameters.render}}/images',
        mountPath: '/data/runs/{{inputs.parameters.run}}/images',
        readOnly: true,
      },
    ],
  },
};

local scoreTemplate = inputs(['run', 'render', 'revision']) {
  name: 'score',
  script: {
    image: notebookImage,
    command: ['bash'],
    source: cloneScript + |||
      run='/data/runs/{{inputs.parameters.run}}'
      python3 /tmp/coordinator/analysis/mapping_sim/score.py '/data/renders/{{inputs.parameters.render}}' \
        "$run/opensfm/reconstruction.json" --json "$run/score.json"
      python3 - "$run/run.json" "$sha" <<'EOF'
      import json, pathlib, sys
      path = pathlib.Path(sys.argv[1])
      record = json.loads(path.read_text())
      record["score_coordinator_commit"] = sys.argv[2]
      path.write_text(json.dumps(record, indent=1))
      EOF
    |||,
    resources: { requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
    volumeMounts: [dataMount],
  },
};

// The exit handler: whether the steps succeeded or not, save what each pod used, from Mimir, into
// the folder that step wrote (resources.py). An empty render or run is a folder the workflow does
// not write.
local resourcesTemplate = inputs(['render', 'run']) {
  name: 'resources',
  script: {
    image: notebookImage,
    command: ['python3'],
    args: [
      '{{workflow.name}}',
      '{{workflow.creationTimestamp}}',
      '{{inputs.parameters.render}}',
      '{{inputs.parameters.run}}',
    ],
    source: importstr 'resources.py',
    resources: { requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
    volumeMounts: [dataMount],
  },
};

local step(stepName, template, params) = {
  name: stepName,
  template: template.name,
  arguments: { parameters: [{ name: k, value: params[k] } for k in std.objectFields(params)] },
};
local p(n) = '{{workflow.parameters.%s}}' % n;

// written: the render and run directories the steps write, '' for neither, for the exit handler.
local workflowTemplate(wtName, parameters, steps, templates, written) = {
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'WorkflowTemplate',
  metadata: { name: wtName },
  spec: {
    serviceAccountName: serviceAccount.metadata.name,
    entrypoint: 'main',
    onExit: 'exit',
    ttlStrategy: { secondsAfterCompletion: 604800 },
    arguments: { parameters: parameters },
    volumes: [{ name: 'data', persistentVolumeClaim: { claimName: runsPvc.metadata.name } }],
    templates: [
      { name: 'main', steps: [[s] for s in steps] },
      { name: 'exit', steps: [[step('resources', resourcesTemplate, written)]] },
    ] + templates + [resourcesTemplate],
  },
};

// Parameters shared by the templates below.
local configParam = { name: 'config', value: 'analysis/mapping_sim/configs/as-built.yaml' };  // path in coordinator
local revisionParam = { name: 'revision', value: 'main' };  // coordinator branch or tag
local renderArgsParam = { name: 'render-args', value: '' };  // e.g. "--scale 0.25 --limit 10"
local odmArgsParam = { name: 'odm-args', value: '' };  // after the fixed ODM flags

// Render only: renders/<render>/.
local renderWorkflow = workflowTemplate(
  'mapping-sim-render',
  [{ name: 'render' }, configParam, revisionParam, renderArgsParam],
  [step('render', renderTemplate, { render: p('render'), config: p('config'), revision: p('revision'), 'render-args': p('render-args') })],
  [renderTemplate],
  { render: '/data/renders/' + p('render'), run: '' },
);

// Process an existing render into runs/<run>/ and score it.
local processWorkflow = workflowTemplate(
  'mapping-sim-process',
  [{ name: 'run' }, { name: 'render' }, revisionParam, odmArgsParam],
  [
    step('odm', odmTemplate, { run: p('run'), render: p('render'), 'odm-args': p('odm-args') }),
    step('score', scoreTemplate, { run: p('run'), render: p('render'), revision: p('revision') }),
  ],
  [odmTemplate, scoreTemplate],
  { render: '', run: '/data/runs/' + p('run') },
);

// Both, with the render and the run sharing one name.
local allWorkflow = workflowTemplate(
  'mapping-sim',
  [{ name: 'name' }, configParam, revisionParam, renderArgsParam, odmArgsParam],
  [
    step('render', renderTemplate, { render: p('name'), config: p('config'), revision: p('revision'), 'render-args': p('render-args') }),
    step('odm', odmTemplate, { run: p('name'), render: p('name'), 'odm-args': p('odm-args') }),
    step('score', scoreTemplate, { run: p('name'), render: p('name'), revision: p('revision') }),
  ],
  [renderTemplate, odmTemplate, scoreTemplate],
  { render: '/data/renders/' + p('name'), run: '/data/runs/' + p('name') },
);

{
  runsPv: runsPv,
  runsPvc: runsPvc,
  serviceAccount: serviceAccount,
  workflowRole: workflowRole,
  workflowRoleBinding: workflowRoleBinding,
  renderWorkflow: renderWorkflow,
  processWorkflow: processWorkflow,
  allWorkflow: allWorkflow,
}
