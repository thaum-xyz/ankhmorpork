local esphome = import 'apps/esphome.libsonnet';
local homeassistant = import 'apps/homeassistant.libsonnet';
local timescaledb = import 'apps/timescaledb.libsonnet';
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
  postgres: {
    credentialsUser: externalsecret(
      {
        name: 'pg-user',
        namespace: config.postgres.namespace,
      },
      'doppler-auth-api',
      {
        password: config.postgres.db.userPassRef,
      }
    ) + {
      spec+: {
        target+: {
          template+: {
            type: 'kubernetes.io/basic-auth',
            data: {
              username: config.postgres.db.user,
              password: '{{ .password }}',
            },
          },
        },
      },
    },
    credentialsAdmin: externalsecret(
      {
        name: 'pg-admin',
        namespace: config.postgres.namespace,
      },
      'doppler-auth-api',
      {
        password: config.postgres.db.adminPassRef,
      }
    ) + {
      spec+: {
        target+: {
          template+: {
            type: 'kubernetes.io/basic-auth',
            data: {
              username: 'postgres',
              password: '{{ .password }}',
            },
          },
        },
      },
    },
    cluster: {
      apiVersion: 'postgresql.cnpg.io/v1',
      kind: 'Cluster',
      metadata: {
        name: config.postgres.name,
        namespace: config.postgres.namespace,
      },
      spec: {
        instances: 1,
        monitoring: {
          enablePodMonitor: true,
        },
        superuserSecret: {
          name: $.postgres.credentialsAdmin.metadata.name,
        },
        bootstrap: {
          initdb: {
            database: config.postgres.db.name,
            owner: config.postgres.db.user,
            secret: {
              name: $.postgres.credentialsUser.metadata.name,
            },
          },
        },
        resources: config.postgres.resources,
        storage: config.postgres.storage,
      },
    },
    svc: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        annotations: {
          'metallb.universe.tf/address-pool': 'default',
        },
        name: 'postgres-lb',
        namespace: config.timescaledb.namespace,
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
  timescaledb: timescaledb(config.timescaledb) + {
    credentials: externalsecret(
      {
        name: 'timescaledb',
        namespace: config.timescaledb.namespace,
      },
      'doppler-auth-api',
      {
        POSTGRES_USER: config.timescaledb.database.userRef,
        POSTGRES_PASSWORD: config.timescaledb.database.passRef,
      }
    ),
    service+:: {
      metadata+: {
        annotations: {
          'metallb.universe.tf/address-pool': 'default',
        },
      },
      spec+: {
        // Needed because HomeAssistant is on host network
        loadBalancerIP: '192.168.2.93',
        type: 'LoadBalancer',
        clusterIP:: null,
      },
    },
    prometheusRule+: {
      spec+: {
        groups: removeAlerts(
          ['PostgreSQLCacheHitRatio'],
          'PostgreSQL',
          super.groups,
        ),
      },
    },
  },
  homeassistant: homeassistant(config.homeassistant) + {
    credentials: externalsecret(
      {
        name: config.homeassistant.apiTokenSecretKeySelector.name,
        namespace: config.homeassistant.namespace,
      },
      'doppler-auth-api',
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
            nodeSelector: {
              'kubernetes.io/arch': 'arm64',
            },
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
