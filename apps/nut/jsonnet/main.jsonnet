local exporter = (import 'apps/prometheus-exporter.libsonnet');
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = exporter(config) + {
  nutConfig: externalsecret({
                              name: config.name,
                              namespace: config.namespace,
                            },
                            'doppler-auth-api',
                            config.credentialsRefs),
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
  podMonitor+:: {},
  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $.podMonitor.metadata,
    spec: {
      clusterIP: 'None',
      ports: [{
        name: $.deployment.spec.template.spec.containers[0].ports[0].name,
        port: config.port,
      }],
      selector: $.deployment.spec.selector.matchLabels,
    },
  },
  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $.podMonitor.metadata,
    spec: $.podMonitor.spec {
      podMetricsEndpoints:: {},
      endpoints: $.podMonitor.spec.podMetricsEndpoints,
    },
  },
  probe: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'Probe',
    metadata: $.deployment.metadata,
    spec: {
      interval: '30s',
      prober: {
        url: $.service.metadata.name + '.' + $.service.metadata.namespace + '.svc:' + std.toString(config.port),
        path: '/ups_metrics',
      },
      targets: {
        staticConfig: {
          static: config.upses,
          relabelingConfigs: [
            {
              sourceLabels: ['__param_target'],
              targetLabel: '__param_server',
            },
          ],
        },
      },
    },
  },
  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $.deployment.metadata {
      labels+: {
        prometheus: 'k8s',
        role: 'alert-rules',
      },
    },
    spec: {
      groups: [{
        name: 'nut.alerts',
        rules: [
          {
            alert: 'NUTExporterDown',
            annotations: {
              description: 'NUT exporter {{ $labels.instance }} is down or cannot contact UPS. Check logs for more information.',
              summary: 'NUT exporter is down or cannot contact UPS.',
            },
            expr: 'absent(network_ups_tools_ups_status)',
            'for': '5m',
            labels: {
              severity: 'critical',
            },
          },
          {
            alert: 'UPSOnBattery',
            annotations: {
              description: 'UPS {{ $labels.instance }} is now supplying power to the system from the battery.',
              summary: 'UPS has gone on battery power',
            },
            expr: 'network_ups_tools_ups_status{flag="OL"} == 0',
            labels: {
              severity: 'warning',
            },
          },
          {
            alert: 'UPSBatteryCritical',
            annotations: {
              description: 'UPS {{ $labels.instance }} has less than {{ $value | humanizePercentage }} of battery remaining.',
              summary: "UPS exited 'online' mode",
            },
            expr: 'network_ups_tools_battery_charge < 50',
            labels: {
              severity: 'critical',
            },
          },
        ],
      }],
    },
  },
};


{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
