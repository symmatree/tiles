local symmMixin = import 'symm-mixin.libsonnet';

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
  symmMixin  {
    _config+:: {
    }
  },
  {
    folder: 'Symm',
    namespace: 'symm-mixin',
  },
)
