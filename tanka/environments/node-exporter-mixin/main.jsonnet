local nodeExporterMixin = import 'github.com/prometheus/node_exporter/docs/node-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  nodeExporterMixin {
    _config+:: {
      nodeExporterSelector: 'job="integrations/node_exporter"',
    },
  },
  {
    folder: 'Node Exporter',
    namespace: 'alloy',
  },
)
