local corednsMixin = import 'github.com/povilasv/coredns-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  corednsMixin,
  {
    folder: 'CoreDNS',
    namespace: 'kube-system',
  },
)
