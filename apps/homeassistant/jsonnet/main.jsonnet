local homeassistant = import './homeassistant.libsonnet';
local sealedsecret = (import '../../../lib/sealedsecret.libsonnet').sealedsecret;

local configYAML = (importstr './settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  apiTokenSecretKeySelector: {
    name: 'credentials',
    key: 'token',
  },
};

local all = homeassistant(config) + {
  credentials: sealedsecret(config.apiTokenSecretKeySelector.name, config.namespace, { [config.apiTokenSecretKeySelector.key]: config.encryptedAPIToken }),
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
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
