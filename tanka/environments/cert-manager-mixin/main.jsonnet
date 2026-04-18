local certManagerMixin = import 'github.com/imusmanmalik/cert-manager-mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  certManagerMixin,
  {
    folder: 'Cert Manager',
    namespace: 'cert-manager',
  },
)
