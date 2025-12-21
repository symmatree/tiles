// This has more interesting alerts than the default one in jsonnet-libs.
local argocdMixin = import 'github.com/adinhodovic/argo-cd-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  argocdMixin  {
    _config+:: {
      grafanaUrl: 'https://grafana.tiles-test.symmatree.com',
      argocdUrl: 'https://argocd.tiles-test.symmatree.com',
    }
  }
  ,
  {
    folder: 'ArgoCD',
    namespace: 'argocd',
  },
)
