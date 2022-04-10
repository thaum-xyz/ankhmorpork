local defaults = {
  local defaults = self,
  name: 'timescaledb',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  exporterImage: "quay.io/prometheuscommunity/postgres-exporter:latest",
  resources: {
    requests: { cpu: '100m', memory: '300Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'timescaledb',
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
      # storageClassName: 'local-path',
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '2Gi',
        },
      },
    },
  },
  database: {
    user: "postgres",
    pass: "",
    name: "postgres",
  },
  /*mixin:: {
    ruleLabels: {},
    _config: {
      runbookURLPattern: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/%s',
      jobSelector: 'job="%s", namespace="%s"' % (defaults.name, defaults.namespace),
    },
  },*/
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

  /*mixin:: {
    (import 'github.com/prometheus-community/postgres_exporter/postgres_mixin/mixin.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/lib/add-runbook-links.libsonnet') + {
      _config+:: g._config.mixin._config,
    },
  }*/

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
        },{
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
    apiVersion: "v1",
    kind: "Secret",
    metadata: $._metadata,
    data: {
      POSTGRES_USER: $._config.database.user,
      POSTGRES_PASSWORD: $._config.database.pass,
    },
  },

  statefulSet: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [
        {
          name: "POSTGRES_DB",
          value: $._config.database.name,
        },{
          name: "TIMESCALEDB_TELEMETRY",
          value: "basic",
        },{
          name: "TS_TUNE_MEMORY",
          value: "300MB",  // FIXME: Take value from resource limits
        },{
          name: "TS_TUNE_NUM_CPUS",
          value: "1",  // FIXME: Take value from resource limits
        }
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
      }],
      resources: $._config.resources,
    },

    local e = {
      name: "exporter",
      image: $._config.exporterImage,
      env: [
        {
          name: "DATA_SOURCE_URI",
          value: "127.0.0.1?sslmode=disable",
        },{
          name: "DATA_SOURCE_USER",
          value: "$(POSTGRES_USER)",
        },{
          name: "DATA_SOURCE_PASS",
          value: "$(POSTGRES_PASSWORD)",
        },{
          name: "PG_EXPORTER_AUTO_DISCOVER_DATABASES",
          value: "true",
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
            "kubectl.kubernetes.io/default-container": c.name,
          },
        },
        spec: {
          containers: [c,e],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
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

  // TODO: include https://github.com/prometheus-community/postgres_exporter/tree/master/postgres_mixin
  /*prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata,
    spec: {
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
        }],
      }],
    },
  },*/
}
