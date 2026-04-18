local alloyMixin = import 'github.com/grafana/alloy/operations/alloy-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  alloyMixin,
  {
    folder: 'Alloy',
    namespace: 'alloy',
  },
)
