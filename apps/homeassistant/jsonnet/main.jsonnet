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
  esphomedevices: {
    metadata:: {
      name: "esp-dev",
      namespace: config.homeassistant.namespace,
      labels: {
        "app.kubernetes.io/name": "esp-dev",
        "app.kubernetes.io/part-of": "homeassistant",
      },
    },
    endpoints: {
      apiVersion: "v1",
      kind: "Endpoints",
      metadata: all.esphomedevices.metadata,
      subsets: [{
        addresses: [
          { ip: "192.168.2.221" },
          { ip: "192.168.2.224" }
        ],
        ports: [{
          port: 80,
          name: "http",
        }],
      }]
    },
    service: {
      apiVersion: "v1",
      kind: "Service",
      metadata: all.esphomedevices.metadata,
      spec: {
        clusterIP: "None",
        ports: all.esphomedevices.endpoints.subsets[0].ports,
      },
    },
    serviceMonitor: {
      apiVersion: "monitoring.coreos.com/v1",
      kind: "ServiceMonitor",
      metadata: all.esphomedevices.metadata,
      spec: {
        endpoints: [{
          interval: "120s",
          port: all.esphomedevices.endpoints.subsets[0].ports[0].name,
        }],
        selector: {
          matchLabels: all.esphomedevices.service.metadata.labels,
        },
      },
    },
    prometheusRule: {
      apiVersion: "monitoring.coreos.com/v1",
      kind: "PrometheusRule",
      metadata: all.esphomedevices.metadata + {
        labels: {
          prometheus: "k8s",
          role: "alert-rules",
        },
      },
      spec: {
        groups: [{
          name: "esphome.alerts",
          rules: [{
            alert: "ESPHomeSensorFailure",
            annotations: {
              summary: "ESPHome sensor failed",
              description: "ESPHome sensor named {{ $labels.name }} with {{ $labels.id }} on {{ $labels.instance }} device failed to gather data for 4h.",
            },
            expr: "esphome_sensor_failed != 0",
            "for": "8h",
            labels: {
              severity: "warning",
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
          "metallb.universe.tf/address-pool": "default"
        },
      },
      spec+: {
        loadBalancerIP: "192.168.2.94",
        type: "LoadBalancer",
        clusterIP:: null,
      },
    },
  },
  homeassistant: homeassistant(config.homeassistant) + {
    credentials: sealedsecret(
      {
        name: config.homeassistant.apiTokenSecretKeySelector.name,
        namespace: config.homeassistant.namespace,
      },
      { [config.homeassistant.apiTokenSecretKeySelector.key]: config.homeassistant.encryptedAPIToken }
    ),
    configs: {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: $.homeassistant.statefulSet.metadata {
        name: "homeassistant-configs",
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
          metadata+: {
            annotations: {
              'checksum.config/md5': std.md5(std.toString($.homeassistant.configs.data)),
            },
          },
          spec+: {
            containers: std.map(function(c) c {
              volumeMounts+: [{
                mountPath: '/config/configuration.yaml',
                name: 'configs',
                subPath: 'configuration.yaml',
                readOnly: true,
              },{
                mountPath: '/config/customize.yaml',
                name: 'configs',
                subPath: 'customize.yaml',
                readOnly: true,
              },{
                mountPath: '/config/scripts.yaml',
                name: 'configs',
                subPath: 'scripts.yaml',
                readOnly: true,
              },],
            }, super.containers),
            nodeSelector: {
              'kubernetes.io/arch': 'arm64',
            },
            volumes+: [{
              configMap: {
                name: $.homeassistant.configs.metadata.name,
              },
              name: "configs"
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
  }
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
