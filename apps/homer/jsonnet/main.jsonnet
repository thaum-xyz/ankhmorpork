local homer = import './homer.libsonnet';
local configData = importstr './homer-configuration.yml';

local config = (import './deployment-config.json') + {
  configData: configData,
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
