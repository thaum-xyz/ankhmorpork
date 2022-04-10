local defaults = {
  namespace:: error 'must provide namespace',
  commonLabels:: {
    'app.kubernetes.io/name': 'windows-exporter',
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },

  nodes:: [],

  mixin:: {
    ruleLabels: {},
    _config: {
      runbookURLPattern: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/%s',
      kubeStateMetricsSelector: 'job="kube-state-metrics"',
      windowsExporterSelector: 'job="windows-exporter"',
    },
  },
};

function(params) {
  local windows = self,
  _config:: defaults + params,
  _metadata:: {
    labels: windows._config.commonLabels,
    namespace: windows._config.namespace,
    name: 'windows-exporter',
  },

  mixin::
    // Import decomposed kubernetes mixin as only parts of it are needed for this component
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/rules/windows.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/dashboards/defaults.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/dashboards/windows.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/config.libsonnet') +
    {
      _config+:: windows._config.mixin._config,
    },

  endpoints: {
    apiVersion: 'v1',
    kind: 'Endpoints',
    metadata: windows._metadata,
    subsets: [{
      addresses: [{ ip: x } for x in windows._config.nodes],
      ports: [{
        name: 'http',
        port: 9182,
      }],
    }],
  },
  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: windows._metadata,
    spec: {
      clusterIP: 'None',
      ports: windows.endpoints.subsets[0].ports,
    },
  },
  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: windows._metadata,
    spec: {
      jobLabel: 'windows-exporter',
      endpoints: [{
        interval: '60s',
        port: windows.endpoints.subsets[0].ports[0].name,
      }],
      selector: {
        matchLabels: windows.service.metadata.labels,
      },
    },
  },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: windows._metadata {
      name: 'kubernetes-windows-monitoring-rules',
      labels+: windows._config.mixin.ruleLabels,
    },
    spec: {
      local r = if std.objectHasAll(windows.mixin, 'prometheusRules') then windows.mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll(windows.mixin, 'prometheusAlerts') then windows.mixin.prometheusAlerts.groups else [],
      groups: a + r,
    },
  },
}
