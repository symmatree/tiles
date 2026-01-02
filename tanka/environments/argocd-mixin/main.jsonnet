// This has more interesting alerts than the default one in jsonnet-libs.
local argocdMixin = import 'github.com/adinhodovic/argo-cd-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';
local APP = std.parseJson(std.extVar('ARGOCD_APP_PARAMETERS'));
// assert APP.cluster_name != null && APP.cluster_name != "";

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
