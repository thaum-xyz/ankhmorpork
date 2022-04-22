local all = {
  _metadata:: {
    name: 'ingress-nginx',
    namespace: 'ingress-nginx',
    labels: {
      'app.kubernetes.io/name': 'ingress-nginx',
      'app.kubernetes.io/instance': 'ingress-nginx',
    },
  },

  mixin:: (import 'github.com/nlamirault/monitoring-mixins/mixins/nginx-ingress-controller-mixin/mixin.libsonnet'),

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
  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata {
      labels+: {
        prometheus: 'k8s',
        role: 'alert-rules',
      },
    },
    spec: {
      local r = if std.objectHasAll($.mixin, 'prometheusRules') then $.mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll($.mixin, 'prometheusAlerts') then $.mixin.prometheusAlerts.groups else [],
      groups: a + r,
    },
  },
  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata {
      name: 'metrics',
    },
    spec: {
      type: 'ClusterIP',
      ports: [{
        name: 'metrics',
        port: 10254,
        protocol: 'TCP',
        targetPort: 'metrics',
      }],
      selector: $._metadata.labels {
        'app.kubernetes.io/component': 'controller',
      },
    },
  },
  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: [{
        interval: '30s',
        port: 'metrics',
        honorLabels: true,
      }],
      jobLabel: 'app.kubernetes.io/name',
      selector: {
        matchLabels: $.service.metadata.labels,
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
