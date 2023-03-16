local defaults = {
  local defaults = self,
  name: 'timescaledb',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  exporterImage: 'quay.io/prometheuscommunity/postgres-exporter:latest',
  resources: {
    requests: { cpu: '100m', memory: '300Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'database',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  storage: {
    name: 'timescaledb-data',
    pvcSpec: {
      // storageClassName: 'local-path',
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '2Gi',
        },
      },
    },
  },
  database: {
    user: 'postgres',
    pass: '',
    name: 'postgres',
  },
  mixin:: {
    ruleLabels: {
      prometheus: 'k8s',
      role: 'alert-rules',
    },
    _config: {
      runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/postgresql/%s',
      postgresExporterSelector: 'job="%s", namespace="%s"' % [defaults.name, defaults.namespace],
    },
  },
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  // Safety check
  assert std.isObject($._config.resources),

  mixin:: (import 'github.com/prometheus-community/postgres_exporter/postgres_mixin/mixin.libsonnet') +
          (import 'github.com/kubernetes-monitoring/kubernetes-mixin/lib/add-runbook-links.libsonnet') +
          {
            _config+:: $._config.mixin._config,
          },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata {
      labels+: $._config.mixin.ruleLabels,
    },
    spec: {
      local r = if std.objectHasAll($.mixin, 'prometheusRules') then $.mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll($.mixin, 'prometheusAlerts') then $.mixin.prometheusAlerts.groups else [],
      groups: [{
        name: 'timescaledb.alerts',
        rules: [{
          alert: 'timescaledbExporterDown',
          annotations: {
            description: 'TimescaleDB exporter instance {{ $labels.instance }} is down',
            summary: 'TimescaleDB exporter is down',
          },
          expr: 'up{job=~"timescaledb.*",namespace="%s"} == 0' % $._metadata.namespace,
          'for': '30m',
          labels: {
            severity: 'warning',
          },
        }],
      }] + a + r,
    },
  },

  dashboards: {
    apiVersion: 'v1',
    kind: 'ConfigMapList',
    items: [
      {
        local dashboardName = 'grafana-dashboard-' + std.strReplace(name, '.json', ''),
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: $._metadata {
          name: dashboardName,
          labels+: {
            'dashboard.grafana.com/load': 'true',
          },
        },
        data: { [name]: std.manifestJsonEx($.mixin.grafanaDashboards[name], '    ') },
      }
      for name in std.objectFields($.mixin.grafanaDashboards)
    ],
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: $._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [
        {
          name: 'psql',
          targetPort: $.statefulSet.spec.template.spec.containers[0].ports[0].name,
          port: 5432,
        },
        {
          name: 'metrics',
          targetPort: $.statefulSet.spec.template.spec.containers[1].ports[0].name,
          port: 9187,
        },
      ],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  credentials: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: $._metadata,
    data: {
      POSTGRES_USER: $._config.database.user,
      POSTGRES_PASSWORD: $._config.database.pass,
    },
  },

  additionalSQL: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: $._metadata {
      name: 'additional-sql',
    },
    data: {
      'alter-extension.sql': |||
        CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
        ALTER EXTENSION timescaledb UPDATE;
      |||,
    },
  },

  statefulSet: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [
        {
          name: 'POSTGRES_DB',
          value: $._config.database.name,
        },
        {
          name: 'TIMESCALEDB_TELEMETRY',
          value: 'basic',
        },
        {
          name: "TS_TUNE_NUM_CPUS",
          valueFrom: {
            resourceFieldRef: {
              containerName: $._config.name,
              resource: "limits.cpu",
              divisor: "1",
            },
          },
        },
        {
          name: "TS_TUNE_MEMORY",
          valueFrom: {
            resourceFieldRef: {
              containerName: $._config.name,
              resource: "limits.memory",
              divisor: "1Mi",
            },
          },
        },
      ],
      envFrom: [{
        secretRef: {
          name: $.credentials.metadata.name,
        },
      }],
      ports: [{
        containerPort: 5432,
        name: 'psql',
      }],
      securityContext: {
        privileged: false,
      },
      volumeMounts: [{
        mountPath: '/var/lib/postgresql/data',
        name: $._config.storage.name,
      }, {
        mountPath: '/docker-entrypoint-initdb.d/alter-extension.sql',
        name: 'alter-extension',
        subPath: 'alter-extension.sql',
      }],
      resources: $._config.resources,
    },

    local e = {
      name: 'exporter',
      image: $._config.exporterImage,
      args: [
        "--no-collector.database",
      ],
      env: [
        {
          name: 'DATA_SOURCE_URI',
          value: '127.0.0.1?sslmode=disable',
        },
        {
          name: 'DATA_SOURCE_USER',
          value: '$(POSTGRES_USER)',
        },
        {
          name: 'DATA_SOURCE_PASS',
          value: '$(POSTGRES_PASSWORD)',
        },
        {
          name: 'PG_EXPORTER_AUTO_DISCOVER_DATABASES',
          value: 'true',
        },
      ],
      envFrom: [{
        secretRef: {
          name: $.credentials.metadata.name,
        },
      }],
      ports: [{
        containerPort: 9187,
        name: 'metrics',
      }],
      securityContext: {
        privileged: false,
      },
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: $._metadata,
    spec: {
      serviceName: $.service.metadata.name,
      replicas: 1,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          labels: $._config.commonLabels,
          annotations: {
            'kubectl.kubernetes.io/default-container': c.name,
          },
        },
        spec: {
          containers: [c, e],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          volumes: [{
            name: 'alter-extension',
            configMap: {
              name: $.additionalSQL.metadata.name,
            },
          }],
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: $._config.storage.name,
        },
        spec: $._config.storage.pvcSpec,
      }],
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: [{
        interval: '30s',
        port: $.service.spec.ports[1].name,
      }],
      selector: {
        matchLabels: $._config.selectorLabels,
      },
    },
  },
}
