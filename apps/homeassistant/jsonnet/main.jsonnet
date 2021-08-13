local homeassistant = import 'github.com/thaum-xyz/jsonnet-libs/apps/homeassistant/homeassistant.libsonnet';
local esphome = import 'github.com/thaum-xyz/jsonnet-libs/apps/esphome/esphome.libsonnet';
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  homeassistant+: {
    apiTokenSecretKeySelector: {
      name: 'credentials',
      key: 'token',
    },
  },
};

local all = {
  homeassistant: homeassistant(config['homeassistant']) + {
    credentials: sealedsecret(
      {
        name: config.homeassistant.apiTokenSecretKeySelector.name,
        namespace: config.homeassistant.namespace,
      },
      { [config.homeassistant.apiTokenSecretKeySelector.key]: config.homeassistant.encryptedAPIToken }
    ),
    ingress+: {
      metadata+: {
        labels+: {
          probe: 'enabled',
        },
        annotations+: {
          'nginx.ingress.kubernetes.io/proxy-send-timeout': '3600',
          'nginx.ingress.kubernetes.io/proxy-read-timeout': '3600',
        },
      },
    },
    statefulSet+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: {
              'kubernetes.io/arch': 'arm64',
            },
          },
        },
      },
    },
    prometheusRule+: {
      metadata+: {
        labels+: {
          prometheus: 'k8s',
          role: 'alert-rules',
        },
      },
    },
  }
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
