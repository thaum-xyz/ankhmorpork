local postgres = import 'apps/cloudnative-pg-cluster.libsonnet';
local esphome = import 'apps/esphome.libsonnet';
local homeassistant = import 'apps/homeassistant.libsonnet';
local externalTargets = import 'externalTargets.libsonnet';
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;
local removeAlerts = (import 'utils/mixins.libsonnet').removeAlerts;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = {
  esphomedevices: externalTargets(config.espdevices) {
    _metadata+:: {
      labels+: {
        'app.kubernetes.io/part-of': 'homeassistant',
      },
    },
    prometheusRule: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PrometheusRule',
      metadata: $.esphomedevices._metadata {
        labels: {
          prometheus: 'k8s',
          role: 'alert-rules',
        },
      },
      spec: {
        groups: [{
          name: 'esphome.alerts',
          rules: [{
            alert: 'ESPHomeSensorFailure',
            annotations: {
              summary: 'ESPHome sensor failed',
              description: 'ESPHome sensor named {{ $labels.name }} with {{ $labels.id }} on {{ $labels.instance }} device failed to gather data for 4h.',
            },
            expr: 'esphome_sensor_failed != 0',
            'for': '8h',
            labels: {
              severity: 'warning',
            },
          }],
        }],
      },
    },
  },
  esphome: esphome(config.esphome) + {
    service+: {
      metadata+: {
        annotations: {
          'metallb.universe.tf/address-pool': 'default',
        },
      },
      spec+: {
        loadBalancerIP: '192.168.2.94',
        type: 'LoadBalancer',
        clusterIP:: null,
      },
    },
  },
  postgres: postgres(config.postgres) + {
    svc: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        annotations: {
          'metallb.universe.tf/address-pool': 'default',
        },
        name: 'postgres-lb',
        namespace: config.postgres.namespace,
      },
      spec: {
        // Needed because HomeAssistant is on host network
        loadBalancerIP: '192.168.2.93',
        type: 'LoadBalancer',
        ports: [{
          name: 'postgres',
          port: 5432,
          protocol: 'TCP',
          targetPort: 5432,
        }],
        selector: {
          'cnpg.io/cluster': 'postgres',
          role: 'primary',
        },
      },
    },
  },

  homeassistant: homeassistant(config.homeassistant) + {
    credentials: externalsecret(
      {
        name: config.homeassistant.apiTokenSecretKeySelector.name,
        namespace: config.homeassistant.namespace,
      },
      config.homeassistant.externalSecretStoreName,
      { [config.homeassistant.apiTokenSecretKeySelector.key]: config.homeassistant.apiTokenRef }
    ),
    configs: {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: $.homeassistant.statefulSet.metadata {
        name: 'homeassistant-configs',
      },
      data: {
        'configuration.yaml': importstr '../config/configuration.yaml',
        'customize.yaml': importstr '../config/customize.yaml',
        'scripts.yaml': importstr '../config/scripts.yaml',
      },
    },
    ingress+: {
      metadata+: {
        labels+: {
          probe: 'enabled',
        } + config.homeassistant.ingress.labels,
        annotations+: {
          'nginx.ingress.kubernetes.io/proxy-send-timeout': '3600',
          'nginx.ingress.kubernetes.io/proxy-read-timeout': '3600',
        },
      },
    },
    statefulSet+: {
      spec+: {
        template+: {
          metadata+: {
            annotations: {
              'checksum.config/md5': std.md5(std.toString($.homeassistant.configs.data)),
            },
          },
          spec+: {
            priorityClassName: 'production-high',
            containers: std.map(function(c) c {
              volumeMounts+: [{
                mountPath: '/config/configuration.yaml',
                name: 'configs',
                subPath: 'configuration.yaml',
                readOnly: true,
              }, {
                mountPath: '/config/customize.yaml',
                name: 'configs',
                subPath: 'customize.yaml',
                readOnly: true,
              }, {
                mountPath: '/config/scripts.yaml',
                name: 'configs',
                subPath: 'scripts.yaml',
                readOnly: true,
              }],
            }, super.containers),
            volumes+: [{
              configMap: {
                name: $.homeassistant.configs.metadata.name,
              },
              name: 'configs',
            }],
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
  },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
