local api = import 'lib/mealie-api.libsonnet';
local frontend = import 'lib/mealie-frontend.libsonnet';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {};

local all = {
  frontend: frontend(config.common + config.frontend) + {
    /*  secret: sealedsecret({
      name: config.credentialsSecretRef,
      namespace: config.namespace,
      labels: $._config.commonLabels,
    }, config.envs),*/
    ingress+: {
      metadata+: {
        /*labels+: {
          probe: 'enabled',
        },*/
        annotations+: {
          //'nginx.ingress.kubernetes.io/proxy-body-size': '200M',  // Needed for migrations and bulk imports
          'nginx.ingress.kubernetes.io/proxy-body-size': '2M',  // Prevent uploading large images
        },
      },
    },
  },
  api: api(config.common + config.api) + {
    /*  secret: sealedsecret({
      name: config.credentialsSecretRef,
      namespace: config.namespace,
      labels: $._config.commonLabels,
    }, config.envs),*/
  },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
