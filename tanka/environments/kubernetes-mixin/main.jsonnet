local k8sMixin = import 'github.com/kubernetes-monitoring/kubernetes-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  k8sMixin {
    _config+:: {
      // Correct defaults:
      // kubeControllerManagerSelector: 'job="kube-controller-manager"',
      // kubeSchedulerSelector: 'job="kube-scheduler"',
      // Doesnt exist:
      // kubeProxySelector: 'job="kube-proxy"',

      kubeApiserverSelector: 'job="integrations/kubernetes/kube-apiserver"',
      kubeStateMetricsSelector: 'job="integrations/kubernetes/kube-state-metrics"',
      cadvisorSelector: 'job="integrations/kubernetes/cadvisor"',
      kubeletSelector: 'job="integrations/kubernetes/kubelet"',
      nodeExporterSelector: 'job="integrations/node_exporter"',
      grafanaK8s+:: {
        grafanaTimezone: 'browser',
      },
      showMultiCluster: true,
    },
  },
  {
    folder: 'Kubernetes',
    namespace: 'alloy',
    tags: ['kubernetes'],
    dashboardsToDrop: [
      'proxy',
      'k8s-resources-windows-cluster',
      'k8s-resources-windows-namespace',
      'k8s-resources-windows-pod',
      'k8s-windows-cluster-rsrc-use',
      'k8s-windows-node-rsrc-use',
    ],
    ruleGroupsToDrop: [
      'kubernetes-system-kube-proxy',
    ],
    alertsToDrop: {
      'kubernetes-resources': ['KubeCPUOvercommit', 'KubeMemoryOvercommit'],
    },
  },
)