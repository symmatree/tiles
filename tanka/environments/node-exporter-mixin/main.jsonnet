local nodeExporterMixin = import 'github.com/prometheus/node_exporter/docs/node-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

// One string, used both as the mixin's selector and as the anchor alertExtraSelectors
// patches, so the two cannot drift apart.
local nodeExporterSelector = 'job="integrations/node_exporter"';

libMonResources.new(
  nodeExporterMixin {
    _config+:: {
      nodeExporterSelector: nodeExporterSelector,
      showMultiCluster: true,
    },
  },
  {
    folder: 'Node Exporter',
    namespace: 'alloy',
    alertSelector: nodeExporterSelector,
    alertExtraSelectors: {
      // Proxmox host memory is a near-static guest allocation, so used% carries no pressure
      // signal there; NodeMemoryMajorPagesFaults still covers these hosts. See #787 and
      // docs/proxmox-monitoring.md for the host_role label.
      NodeMemoryHighUtilization: 'host_role!="proxmox"',
    },
  },
)
