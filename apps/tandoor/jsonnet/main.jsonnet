local postgres = import 'apps/cloudnative-pg-cluster.libsonnet';
local tandoor = import 'tandoor.libsonnet';
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = {
  postgres: postgres(config.postgres),

  local t = tandoor(config.tandoor),
  common: t.common,
  app: t.app,
  static: t.static,
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
