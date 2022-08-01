local exporter = (import 'github.com/thaum-xyz/jsonnet-libs/apps/prometheus-exporter/exporter.libsonnet');

local defaults = {
  name: 'json-exporter',
  namespace: error 'must provide namespace',
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/component': 'exporter',
  },

  config: {},
  targets: [],
};

function(params) exporter(params) {
  _config:: defaults + params,
  _metadata:: $.deployment.metadata {
    labels: $._config.commonLabels {
      'app.kubernetes.io/name': $._config.name,
    },
    namespace: $._config.namespace,
    name: $._config.name,
  },

  configuration: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: $._metadata,
    data: {
      'config.yml': $._config.config,
    },
  },

  deployment+: {
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            'checksum.config/md5': std.md5($._config.config),
          },
        },
        spec+: {
          containers: std.map(function(c) c {
            args+: [
              '--config.file',
              '/etc/json_exporter/config.yml',
            ],
            volumeMounts: [{
              mountPath: '/etc/json_exporter/',
              name: $._metadata.name,
              readOnly: true,
            }],
          }, super.containers),
          volumes: [{
            name: $._metadata.name,
            secret: {
              secretName: $.configuration.spec.template.metadata.name,
            },
          }],
        },
      },
    },
  },
  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [{
        name: $.deployment.spec.template.spec.containers[0].ports[0].name,
        port: $.deployment.spec.template.spec.containers[0].ports[0].containerPort,
        targetPort: $.deployment.spec.template.spec.containers[0].ports[0].name,
      }],
      selector: $.podMonitor.spec.selector.matchLabels,
    },
  },

  // Using ServiceMonitor just to note that Service is necessary and to fail when it disappears
  podMonitor+:: {},
  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: $.podMonitor.spec.podMetricsEndpoints,
      selector: $.podMonitor.spec.selector,
    },
  },

  probe: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'Probe',
    metadata: $._metadata,
    spec: {
      interval: '150s',
      prober: {
        url: $.service.metadata.name + '.' + $.service.metadata.namespace + '.svc:7979',
      },
      targets: {
        staticConfig: {
          static: $._config.targets,
        },
      },
      metricRelabelings: [
        {
          sourceLabels: ['url'],
          targetLabel: 'instance',
        },
        {
          sourceLabels: ['url'],
          targetLabel: 'instance',
          regex: '(https://[a-zA-Z0-9.-]+).*',
          replacement: '$1/',
        },
      ],
    },
  },
}
