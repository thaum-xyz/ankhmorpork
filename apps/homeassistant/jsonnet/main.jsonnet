local homeassistant = import './homeassistant.libsonnet';

local apitoken = import './apitoken.json';
local configYAML = (importstr './settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  apiTokenSecretKeySelector: {
    name: apitoken.spec.template.metadata.name,
    key: 'token',
  },
};

local all = homeassistant(config) + {
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
