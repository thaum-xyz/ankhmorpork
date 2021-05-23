local mealie = import './ghost.libsonnet';

local configYAML = (importstr './settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = mealie(config) + {
  pvc+: {
    metadata: {
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
      annotations+: {
        'nginx.ingress.kubernetes.io/proxy-body-size': '50M',
      },
    },
  },
  // TODO: remove this
  ingressAbout: $.ingress {
    metadata+: {
      name: 'ghost-about',
      annotations+: {
        'nginx.ingress.kubernetes.io/permanent-redirect': 'https://alchemyof.it/about',
      },
    },
    spec+: {
      tls: [{
        hosts: ['blog.ankhmorpork.thaum.xyz'],
        secretName: 'ghost-about-tls',
      }],
      rules: [{
        host: 'blog.ankhmorpork.thaum.xyz',
        http: $.ingress.spec.rules[0].http,
      }],
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
