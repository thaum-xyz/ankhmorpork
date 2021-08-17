local homer = import 'github.com/thaum-xyz/jsonnet-libs/apps/homer/homer.libsonnet';
local siteConfig = importstr '../site-config.yml';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  configData: siteConfig,
};

local all = homer(config) + {
  ingress+: {
    metadata+: {
      labels+: {
        probe: 'enabled',
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
