local homer = import './homer.libsonnet';
local configData = importstr './config.yml';

local config = {
  version: '20.12.19',
  image: 'b4bz/homer:' + self.version,
  namespace: 'homer',
  replicas: 2,
  domain: 'ankhmorpork.thaum.xyz',
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