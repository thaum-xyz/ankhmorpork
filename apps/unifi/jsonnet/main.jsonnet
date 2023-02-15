local externalsecret = (import '../../../lib/jsonnet/utils/externalsecrets.libsonnet').externalsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
};

local all = {
  poller: {
    _metadata:: {
      name: 'poller',
      namespace: config.namespace,
      labels: {
        'app.kubernetes.io/name': 'unifi-poller',
        'app.kubernetes.io/component': 'exporter',
      },
    },
    configuration: externalsecret(
      $.poller._metadata,
      'doppler-auth-api',
      config.poller.credentialsRefs
    ) + {
      spec+: {
        target+: {
          template+: {
            engineVersion: 'v2',
            data: {
              'unifi-poller.conf': config.poller.config,
            },
          },
        },
      },
    },
    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: $.poller._metadata,
    },

    local c = {
      image: config.poller.image,
      name: 'unifi-poller',
      ports: [{
        containerPort: 9130,
        name: 'metrics',
        protocol: 'TCP',
      }],
      resources: config.poller.resources,
      volumeMounts: [{
        mountPath: '/config/unifi-poller.conf',
        name: 'config',
        subPath: 'unifi-poller.conf',
      }],
    },
    deployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: $.poller._metadata,
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app.kubernetes.io/component': 'exporter',
            'app.kubernetes.io/name': 'unifi-poller',
          },
        },
        template: {
          metadata: $.poller._metadata {
            annotations: {
              'checksum.config/md5': std.md5(std.toString(config.poller.credentialsRefs)),
            },
          },
          spec: {
            containers: [c],
            restartPolicy: 'Always',
            volumes: [{
              name: 'config',
              secret: {
                secretName: $.poller.configuration.metadata.name,
              },
            }],
          },
        },
      },
    },
    podMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PodMonitor',
      metadata: $.poller._metadata,
      spec: {
        podMetricsEndpoints: [{
          interval: '30s',
          port: 'metrics',
        }],
        selector: {
          matchLabels: {
            'app.kubernetes.io/component': 'exporter',
            'app.kubernetes.io/name': 'unifi-poller',
          },
        },
      },
    },
  },
  restarter: {
    _metadata:: {
      name: 'restarter',
      namespace: config.namespace,
      labels: {},
    },

    prometheusRule: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PrometheusRule',
      metadata: $.restarter._metadata,
      spec: {
        groups: [{
          name: 'unifi-restarter',
          rules: [
            {
              alert: 'NodeDown',
              expr: 'count by (node) (up{job="node-exporter"} == 0) > 0 AND count by (node) (up{job="kubelet", metrics_path="/metrics"} == 0) > 0',
              'for': '15m',
              annotations: {
                description: 'Metrics from node_exporter and kubelet cannot be gathered for node {{ $labels.node }} suggesting node is down. Alert should be automatically remediated by attempting node power cycle',
                summary: 'Node is down for extended period of time',
              },
              labels: {
                severity: 'warning',  //TODO: change to `info` when automated restarter is finished and deployed
              },
            },
          ],
        }],
      },
    },
  },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
