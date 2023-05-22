local homer = (import 'apps/homer.libsonnet');
//local reloader = (import 'apps/homer-reloader.libsonnet');

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  homer+: {
    configData: '',
  },
};

local all = {
  homer: homer(config.homer) + {
    configmap+:: {},  // This is provided dynamically by homer-reloader
    ingress+: {
      metadata+: {
        labels+: {
          probe: 'enabled',
        },
      },
    },
  },
  reloader: {},  // TBD
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
