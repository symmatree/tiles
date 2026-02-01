local unifi_mcp = import 'unifi_mcp/mcp.libsonnet';

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

unifi_mcp {
  _config+:: {
    cluster_name: APP.cluster_name,
    vault_name: APP.vault_name,
    cluster_issuer: APP.app_settings.cluster_issuer,
  }
}
