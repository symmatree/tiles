local ciliumMixin = import 'github.com/grafana/jsonnet-libs/cilium-enterprise-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  ciliumMixin,
  {
    folder: 'Cilium',
    namespace: 'cilium',
  },
)
