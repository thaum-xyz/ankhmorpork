local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local mealie = import 'github.com/thaum-xyz/jsonnet-libs/apps/mealie/mealie.libsonnet';

local configYAML = (importstr './settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] { credentialsSecretRef: 'envs' };

local all = mealie(config) + {
  secret: sealedsecret({
    name: config.credentialsSecretRef,
    namespace: config.namespace,
    labels: $._config.commonLabels,
  }, config.envs),
  pvc+: {
    spec+: {
      storageClassName: 'managed-nfs-storage',
    },
  },
  ingress+: {
    metadata+: {
      labels+: {
        probe: 'enabled',
      },
      annotations+: {
        //'nginx.ingress.kubernetes.io/proxy-body-size': '200M',  // Needed for migrations and bulk imports
        'nginx.ingress.kubernetes.io/proxy-body-size': '600K',  // Prevent uploading large images
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
