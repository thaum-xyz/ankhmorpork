local defaults = {
  local defaults = self,
  name: 'redis',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  exporterImage: 'oliver006/redis_exporter:latest',
  resources: {
    requests: { cpu: '50m', memory: '70Mi' },
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
  /*config: {

  },*/
  storage: {
    name: 'redis-data',
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
  mixin:: {
    ruleLabels: {
      prometheus: 'k8s',
      role: 'alert-rules',
    },
    _config: {
      runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/redis/%s',
      redisExporterSelector: 'job="%s", namespace="%s"' % [defaults.name, defaults.namespace],
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

  /*mixin:: (import 'github.com/prometheus-community/postgres_exporter/postgres_mixin/mixin.libsonnet') +
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
        name: 'redis.alerts',
        rules: [{
          alert: 'redisExporterDown',
          annotations: {
            description: 'redis exporter instance {{ $labels.instance }} is down',
            summary: 'redis exporter is down',
          },
          expr: 'up{job=~"redis.*",namespace="%s"} == 0' % $._metadata.namespace,
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
  },*/

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
          name: 'redis',
          targetPort: $.statefulSet.spec.template.spec.containers[0].ports[0].name,
          port: 6379,
        },
        {
          name: 'metrics',
          targetPort: $.statefulSet.spec.template.spec.containers[1].ports[0].name,
          port: 9121,
        },
      ],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  statefulSet: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      ports: [{
        containerPort: 6379,
        name: 'redis',
      }],
      securityContext: {
        privileged: false,
      },
      volumeMounts: [{
        mountPath: '/data',
        name: $._config.storage.name,
      }],
      resources: $._config.resources,
    },

    local e = {
      name: 'exporter',
      image: $._config.exporterImage,
      args: [
        '--redis.addr',
        '127.0.0.1',
      ],
      ports: [{
        containerPort: 9121,
        name: 'metrics',
      }],
      resources: {
        requests: {
          cpu: '2m',
          memory: '13Mi',
        },
        limits: {
          memory: '20Mi',
        },
      },
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
          nodeSelector: {
            'kubernetes.io/arch': 'amd64',  // Redis exporter only supports amd64
          },
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
