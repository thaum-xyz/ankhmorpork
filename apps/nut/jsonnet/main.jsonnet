local exporter = (import 'github.com/thaum-xyz/jsonnet-libs/apps/prometheus-exporter/exporter.libsonnet');
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = exporter(config) + {
  nutConfig: sealedsecret({
    name: config.name,
    namespace: config.namespace,
  },config.encryptedCredentials) {
    spec+: {
      template+: {
        data+: {
          NUT_EXPORTER_SERVER: config.ups,
        },
      },
    },      
  },
  deployment+: {
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            'parca.dev/scrape': 'true',
          },
        },
        spec+: {
          containers: std.map(function(c) c {
            envFrom: [{
              secretRef: {
                name: $.nutConfig.metadata.name,
              },
            }],
          }, super.containers),
        },
      },
    },
  },
  podMonitor+: {
    spec+: {
      podMetricsEndpoints+: [$.podMonitor.spec.podMetricsEndpoints[0] + {
        path: '/ups_metrics',
      }],
    },
  },
};


{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
