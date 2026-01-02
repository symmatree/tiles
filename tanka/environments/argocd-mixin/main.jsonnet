// This has more interesting alerts than the default one in jsonnet-libs.
local argocdMixin = import 'github.com/adinhodovic/argo-cd-mixin/mixin.libsonnet';
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
  argocdMixin  {
    _config+:: {
      grafanaUrl: 'https://grafana.' + APP.cluster_name + '.symmatree.com',
      argocdUrl: 'https://argocd.' + APP.cluster_name + '.symmatree.com',
    }
  }
  ,
  {
    folder: 'ArgoCD',
    namespace: 'argocd',
  },
)
