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

local kServiceAccount = k.core.v1.serviceAccount;
local kConfigMap = k.core.v1.configMap;
local kClusterRole = k.rbac.v1.clusterRole;
local kClusterRoleBinding = k.rbac.v1.clusterRoleBinding;
local kRole = k.rbac.v1.role;
local kRoleBinding = k.rbac.v1.roleBinding;
local kPolicyRule = k.rbac.v1.policyRule;
local kSubject = k.rbac.v1.subject;

local name = 'host-maintenance';
local namespace = std.parseJson(importstr 'spec.json').spec.namespace;

// One target a night, 01:00 America/New_York, Monday to Friday: each host is updated and
// rebooted once a week. The host -> node mapping is prod.tfvars' `proxmox_node_name`;
// nuc-g3p-2 carries only the tiles-test VMs.
local targets = [
  { day: 1, target: 'nuc-g2p-1', kind: 'pve', nodes: 'tiles-cp-1 tiles-wk-1' },
  { day: 2, target: 'nuc-g2p-2', kind: 'pve', nodes: 'tiles-cp-2 tiles-wk-2' },
  { day: 3, target: 'nuc-g3p-1', kind: 'pve', nodes: 'tiles-cp-3 tiles-wk-3' },
  { day: 4, target: 'nuc-g3p-2', kind: 'pve', nodes: '' },
  { day: 5, target: 'acebase', kind: 'talos', nodes: 'acebase' },
];

local serviceAccount = kServiceAccount.new(name);

local subjects = [
  kSubject.withKind('ServiceAccount')
  + kSubject.withName(name)
  + kSubject.withNamespace(namespace),
];

// Cordon and drain (kubectl drain).
local clusterRole =
  kClusterRole.new(name)
  + kClusterRole.withRules([
    kPolicyRule.withApiGroups([''])
    + kPolicyRule.withResources(['nodes'])
    + kPolicyRule.withVerbs(['get', 'list', 'watch', 'patch']),
    kPolicyRule.withApiGroups([''])
    + kPolicyRule.withResources(['pods'])
    + kPolicyRule.withVerbs(['get', 'list', 'watch']),
    kPolicyRule.withApiGroups([''])
    + kPolicyRule.withResources(['pods/eviction'])
    + kPolicyRule.withVerbs(['create']),
    kPolicyRule.withApiGroups(['apps'])
    + kPolicyRule.withResources(['daemonsets'])
    + kPolicyRule.withVerbs(['get']),
  ]);

local clusterRoleBinding =
  kClusterRoleBinding.new(name)
  + kClusterRoleBinding.bindRole(clusterRole)
  + kClusterRoleBinding.withSubjects(subjects);

// Argo's executor reports each step's outcome by writing a workflowtaskresult.
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
  + kRoleBinding.withSubjects(subjects);

local script = kConfigMap.new(name) + kConfigMap.withData({
  'host-maintenance.sh': importstr 'host-maintenance.sh',
});

local sshKey = op.item.new(APP.app_settings.ssh_key_secret, 'vaults/' + APP.vault_name + '/items/' + APP.app_settings.ssh_key_secret);
local talosconfig = op.item.new(APP.app_settings.talosconfig_secret, 'vaults/' + APP.vault_name + '/items/' + APP.app_settings.talosconfig_secret);

local param(n) = { name: n, value: '{{inputs.parameters.%s}}' % n };

// One step of host-maintenance.sh. `inputs` become environment variables of the same name
// in upper case; `outputs` are files the step writes under /tmp/outputs.
local step(stepName, inputs=[], outputs=[]) = {
  name: stepName,
  inputs: { parameters: [{ name: i } for i in inputs] },
  outputs: {
    parameters: [
      { name: o, valueFrom: { path: '/tmp/outputs/' + o, default: '' } }
      for o in outputs
    ],
  },
  container: {
    image: APP.app_settings.image,
    // `:main` floats, so a cached copy can be any build.
    imagePullPolicy: 'Always',
    command: ['/bin/bash', '/scripts/host-maintenance.sh', stepName],
    env: [
      { name: 'KIND', value: '{{workflow.parameters.kind}}' },
      { name: 'TARGET', value: '{{workflow.parameters.target}}' },
      { name: 'NODES', value: '{{workflow.parameters.nodes}}' },
      { name: 'WORKFLOW', value: '{{workflow.name}}' },
    ] + [
      { name: std.strReplace(std.asciiUpper(i), '-', '_'), value: '{{inputs.parameters.%s}}' % i }
      for i in inputs
    ],
    volumeMounts: [
      { name: 'scripts', mountPath: '/scripts' },
      { name: 'ssh', mountPath: '/secrets/ssh', readOnly: true },
      { name: 'talos', mountPath: '/secrets/talos', readOnly: true },
    ],
    resources: {
      requests: { cpu: '10m', memory: '32Mi' },
      limits: { memory: '256Mi' },
    },
  },
};

local call(stepName, template, params=[]) = {
  name: stepName,
  template: template,
  [if params != [] then 'arguments']: { parameters: params },
};

local workflowTemplate = {
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'WorkflowTemplate',
  metadata: { name: name },
  spec: {
    serviceAccountName: name,
    entrypoint: 'maintain',
    onExit: 'exit',
    ttlStrategy: { secondsAfterCompletion: 604800 },
    // Lancer is bare metal and on no Proxmox host, and is never a target, so no reboot
    // here takes down the pod driving it.
    nodeSelector: { 'kubernetes.io/hostname': 'lancer' },
    arguments: {
      parameters: [{ name: 'target' }, { name: 'kind' }, { name: 'nodes' }],
    },
    volumes: [
      { name: 'scripts', configMap: { name: name } },
      {
        name: 'ssh',
        secret: {
          secretName: sshKey.metadata.name,
          items: [{ key: 'private-key', path: 'private-key' }],
          defaultMode: std.parseOctal('0440'),
        },
      },
      {
        name: 'talos',
        secret: {
          secretName: talosconfig.metadata.name,
          items: [{ key: 'notesPlain', path: 'notesPlain' }],
          defaultMode: std.parseOctal('0440'),
        },
      },
    ],
    templates: [
      {
        name: 'maintain',
        steps: [
          [call('preflight', 'preflight')],
          [call('drain', 'drain')],
          [call('update-reboot', 'update-reboot')],
          [call('wait-back', 'wait-back', [
            { name: 'boot-ids', value: '{{steps.preflight.outputs.parameters.boot-ids}}' },
            { name: 'host-boot-id', value: '{{steps.update-reboot.outputs.parameters.host-boot-id}}' },
          ])],
          [call('release', 'release')],
        ],
      },
      {
        name: 'exit',
        steps: [
          [call('release', 'release')],
          [call('notify', 'notify', [
            { name: 'status', value: '{{workflow.status}}' },
            { name: 'failures', value: '{{workflow.failures}}' },
          ])],
        ],
      },
      step('preflight', outputs=['boot-ids']),
      step('drain'),
      step('update-reboot', outputs=['host-boot-id']),
      step('wait-back', inputs=['boot-ids', 'host-boot-id']),
      step('release'),
      step('notify', inputs=['status', 'failures']) + {
        container+: {
          env+: [{ name: 'NOTIFY_URL', value: 'http://apprise.apprise.svc:8000/notify/apprise' }],
        },
      },
    ],
  },
};

local cronWorkflow(t) = {
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'CronWorkflow',
  metadata: { name: '%s-%s' % [name, t.target] },
  spec: {
    schedules: ['0 1 * * %d' % t.day],
    timezone: 'America/New_York',
    concurrencyPolicy: 'Forbid',
    // A run the controller missed by more than an hour is skipped rather than started late.
    startingDeadlineSeconds: 3600,
    successfulJobsHistoryLimit: 4,
    failedJobsHistoryLimit: 4,
    workflowSpec: {
      workflowTemplateRef: { name: name },
      arguments: {
        parameters: [
          { name: 'target', value: t.target },
          { name: 'kind', value: t.kind },
          { name: 'nodes', value: t.nodes },
        ],
      },
    },
  },
};

{
  serviceAccount: serviceAccount,
  clusterRole: clusterRole,
  clusterRoleBinding: clusterRoleBinding,
  workflowRole: workflowRole,
  workflowRoleBinding: workflowRoleBinding,
  script: script,
  sshKey: sshKey,
  talosconfig: talosconfig,
  workflowTemplate: workflowTemplate,
  cronWorkflows: { [t.target]: cronWorkflow(t) for t in targets },
}
