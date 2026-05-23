local bondMixin = import 'mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';
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

libMonResources.new(
  bondMixin {
    _config+:: {
      grafanaUrl: 'https://grafana.' + APP.cluster_name + '.symmatree.com',
    },
  },
  {
    folder: 'Bond',
    namespace: 'bond-mixin',
    tags: ['bond'],
  },
)
