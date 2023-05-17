local homer = (import 'apps/homer.libsonnet');
local siteConfig = importstr '../site-config.yml';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  configData: siteConfig,
};

local all = {
 homer: homer(config) + {
    ingress+: {
      metadata+: {
        labels+: {
          probe: 'enabled',
        },
      },
    },
  },
  reloader: {}  # TBD
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
