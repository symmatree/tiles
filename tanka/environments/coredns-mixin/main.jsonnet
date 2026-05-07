local corednsMixin = import 'github.com/povilasv/coredns-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  corednsMixin {
    _config+:: {
      // Alloy / k8s-monitoring scrapes CoreDNS with this job label (see clusterMetrics.kubeDNS.jobLabel
      // in the k8s-monitoring chart). Mixin's default job="kube-dns" does not match → CoreDNSDown false positives.
      corednsSelector: 'job="integrations/kubernetes/kube-dns"',
    },
  },
  {
    folder: 'CoreDNS',
    namespace: 'kube-system',
  },
)
