// Apprise mixin: dashboards + alerts for the Apprise notification backend, plus a
// ServiceMonitor that scrapes Apprise's /metrics so the mixin has data to work with.
// The mixin itself (mixin/) is generic and contributable; tiles-specific wiring lives
// here.
local appriseMixin = import 'mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

local namespace = 'apprise-mixin';

libMonResources.new(
  appriseMixin,
  {
    folder: 'Apprise',
    namespace: namespace,
    tags: ['apprise'],
  },
) + {
  // Scrape the Apprise pod's /metrics (django-prometheus). Apprise lives in the
  // `apprise` namespace; nginx allows in-cluster ranges without auth. The relabel
  // pins job="apprise" so it matches the mixin's default appriseSelector.
  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: 'apprise',
      namespace: namespace,
      labels: { 'app.kubernetes.io/name': 'apprise' },
    },
    spec: {
      namespaceSelector: { matchNames: ['apprise'] },
      selector: { matchLabels: { name: 'apprise' } },
      endpoints: [
        {
          port: 'apprise-http',
          path: '/metrics',
          interval: '30s',
          relabelings: [
            { action: 'replace', targetLabel: 'job', replacement: 'apprise' },
          ],
        },
      ],
    },
  },
}
