local alloyMixin = import 'github.com/grafana/alloy/operations/alloy-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  alloyMixin {
    _config+:: {
      filterSelector: 'job="integrations/alloy"',
    },
  },
  {
    folder: 'Alloy',
    namespace: 'alloy',
    tags: ['alloy'],
  },
)
