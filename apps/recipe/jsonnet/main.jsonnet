local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local mealie = import 'github.com/thaum-xyz/jsonnet-libs/apps/mealie/mealie.libsonnet';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] { credentialsSecretRef: 'envs' };

local all = mealie(config) + {
  secret: sealedsecret({
    name: config.credentialsSecretRef,
    namespace: config.namespace,
    labels: $._config.commonLabels,
  }, config.envs),
  ingress+: {
    metadata+: {
      labels+: {
        probe: 'enabled',
      },
      annotations+: {
        //'nginx.ingress.kubernetes.io/proxy-body-size': '200M',  // Needed for migrations and bulk imports
        'nginx.ingress.kubernetes.io/proxy-body-size': '2M',  // Prevent uploading large images
      },
    },
  },
  deployment+: {
    spec+: {
      template+: {
        spec+: {
          containers: std.map(function(c)
            c {
              env+: [
                {
                  name: "RECIPE_DISABLE_COMMENTS",
                  value: "true",
                },
                {
                  name: "AUTO_BACKUP_ENABLED",
                  value: "true",
                },
                {
                  name: "API_DOCS",
                  value: "false",
                },
              ],
            },
            super.containers,
          ),
        }
      }
    }
  }
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
