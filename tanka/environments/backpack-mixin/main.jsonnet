// Backpack mixin: dashboard for the ELRS TX backpack's WiFi link health, scraped
// from its HTTP /mavlink endpoint by the json_exporter + Probe in the mavproxy
// environment (../mavproxy/main.jsonnet). Dashboards only -- no alerts: the
// backpack is powered off most of the time, so "unreachable" is the normal state
// and would page constantly.
local backpackMixin = import 'mixin/mixin.libsonnet';
local libMonResources = import 'monitoring-resources.libsonnet';

libMonResources.new(
  backpackMixin,
  {
    folder: 'Backpack',
    namespace: 'backpack-mixin',
    tags: ['backpack', 'drone'],
  },
)
