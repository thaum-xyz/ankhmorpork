local defaults = {
  local defaults = self,
  name: 'timescaledb',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
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
  exporter: false,
};

function(params) {
  local h = self,
  _config:: defaults + params,
  _metadata:: {
    name: h._config.name,
    namespace: h._config.namespace,
    labels: h._config.commonLabels,
  },
  // Safety check
  assert std.isObject(h._config.resources),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: h._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: h._metadata,
    spec: {
      ports: [
        {
          name: 'psql',
          targetPort: h.statefulSet.spec.template.spec.containers[0].ports[0].name,
          port: 5432,
        //},{
        //  name: 'metrics',
        //  targetPort: h.statefulSet.spec.template.spec.containers[1].ports[0].name,
        //  port: 9187,
        }
      ],
      selector: h._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  credentials: {
    apiVersion: "v1",
    kind: "Secret",
    metadata: h._metadata,
    data: {
      POSTGRES_USER: h._config.database.user,
      POSTGRES_PASSWORD: h._config.database.pass,
    },
  },

  statefulSet: {
    local c = {
      name: h._config.name,
      image: h._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [
        {
          name: "POSTGRES_DB",
          value: h._config.database.name,
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
          name: h.credentials.metadata.name,
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
        name: h._config.storage.name,
      }],
      resources: h._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: h._metadata,
    spec: {
      serviceName: h.service.metadata.name,
      replicas: 1,
      selector: { matchLabels: h._config.selectorLabels },
      template: {
        metadata: {
          labels: h._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: h.serviceAccount.metadata.name,
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: h._config.storage.name,
        },
        spec: h._config.storage.pvcSpec,
      }],
    },
  },

  [if std.objectHas(params, 'exporter') && std.length(params.domain) > 0 then 'serviceMonitor']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: h._metadata,
    spec: {
      endpoints: [{
        interval: '90s',
        port: h.service.spec.ports[1].name,
      }],
      selector: {
        matchLabels: h._config.selectorLabels,
      },
    },
  },

  [if std.objectHas(params, 'exporter') && std.length(params.domain) > 0 then 'prometheusRule']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: h._metadata,
    // TODO: Create timescaledb monitoring mixin
    // FIXME: Create SLO?
    spec: {
      groups: [{
        name: 'timescaledb.alerts',
        rules: [{
          alert: 'timescaledbDown',
          annotations: {
            description: 'TimescaleDB instance {{ $labels.instance }} is down',
            summary: 'TimescaleDB is down',
          },
          expr: 'up{job=~"timescaledb.*"} == 0',
          'for': '30m',
          labels: {
            severity: 'warning',
          },
        }],
      }],
    },
  },
}
