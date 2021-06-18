local ghost = import 'github.com/thaum-xyz/jsonnet-libs/apps/ghost/ghost.libsonnet';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = ghost(config) + {
  pvc+: {
    metadata+: {
      name: 'data',
    },
    spec+: {
      storageClassName: 'managed-nfs-storage',
    },
  },
  ingress+: {
    metadata+: {
      labels+: {
        probe: 'enabled',
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
