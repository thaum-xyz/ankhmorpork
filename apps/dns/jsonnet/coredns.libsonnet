local podantiaffinity = (import 'utils/pod.libsonnet').antiaffinity;

local defaults = {
  local defaults = self,
  name: 'coredns',
  namespace: error 'must provide namespace',
  image: error 'must provide image',
  version: error 'must provide version',

  loadBalancerIP: error 'must provide loadbalancer IP',
  corefile: error 'must provide Corefile content',
  replicas: 2,

  resources: {
    limits: { cpu: '200m', memory: '170Mi' },
    requests: { cpu: '100m', memory: '30Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'coredns',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'dns-server',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  // Secret can be used to store env variables for coredns
  secretName: '',
  mixin: {
    ruleLabels: {},
    _config: {},
  },
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  mixin:: (import 'github.com/povilasv/coredns-mixin/mixin.libsonnet') +
          (import 'github.com/kubernetes-monitoring/kubernetes-mixin/lib/add-runbook-links.libsonnet') {
            _config+:: $._config.mixin._config,
          },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata {
      labels: $._config.mixin.ruleLabels + $._metadata.labels,
    },
    spec: {
      local r = if std.objectHasAll($.mixin, 'prometheusRules') then $.mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll($.mixin, 'prometheusAlerts') then $.mixin.prometheusAlerts.groups else [],
      groups: a + r,
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
            grafana_dashboard: 'true',
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

  // TODO: Converge into one Service object when k8s LoadBalancer will allow to share UDP and TCP protocols
  serviceTCP: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata { name: $._config.name + '-tcp' },
    spec: {
      type: 'LoadBalancer',
      loadBalancerIP: $._config.loadBalancerIP,
      ports: [{
        name: 'dns-tcp',
        targetPort: 'dns-tcp',
        port: 53,
        protocol: 'TCP',
      }],
      selector: $._config.selectorLabels,
    },
  },

  serviceUDP: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata { name: $._config.name + '-udp' },
    spec: {
      type: 'LoadBalancer',
      loadBalancerIP: $._config.loadBalancerIP,
      ports: [{
        name: 'dns-udp',
        targetPort: 'dns-udp',
        port: 53,
        protocol: 'UDP',
      }],
      selector: $._config.selectorLabels,
    },
  },

  // Since DNS Service would be of NodePort of Loadbalancer type it doesn't make sense to create Service just for ServiceMonitor
  podMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PodMonitor',
    metadata: $._metadata,
    spec: {
      podMetricsEndpoints: [{
        port: 'metrics',
        interval: '30s',
      }],
      selector: {
        matchLabels: $._config.selectorLabels,
      },
    },
  },

  podDisruptionBudget: {
    apiVersion: 'policy/v1',
    kind: 'PodDisruptionBudget',
    metadata: $._metadata,
    spec: {
      minAvailable: 1,
      selector: {
        matchLabels: $._config.selectorLabels,
      },
    },
  },

  config: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: $._metadata {
      name: $._config.name + '-corefile',
    },
    data: {
      Corefile: $._config.corefile,
      //Corefile: 'ok',
    },
  },

  local c = {
    name: $._config.name,
    image: $._config.image,
    imagePullPolicy: 'Always',
    resources: $._config.resources,
    args: ['-conf', '/etc/coredns/Corefile'],
    [if $._config.secretName != '' then 'envFrom']: [
      {
        secretRef: {
          name: $._config.secretName,
        },
      },
    ],
    volumeMounts: [{
      name: 'corefile',
      mountPath: '/etc/coredns',
      readOnly: true,
    }],
    ports: [
      {
        containerPort: 53,
        name: 'dns-udp',
        protocol: 'UDP',
      },
      {
        containerPort: 53,
        name: 'dns-tcp',
        protocol: 'TCP',
      },
      {
        containerPort: 9153,
        name: 'metrics',
        protocol: 'TCP',
      },
    ],
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: {
        add: ['NET_BIND_SERVICE'],
        drop: ['all'],
      },
    },
    livenessProbe: {
      httpGet: {
        path: '/health',
        port: 8080,
        scheme: 'HTTP',
      },
      initialDelaySeconds: 60,
      timeoutSeconds: 5,
      successThreshold: 1,
      failureThreshold: 5,
    },
    readinessProbe: {
      httpGet: {
        path: '/ready',
        port: 8181,
        scheme: 'HTTP',
      },
    },
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      strategy: {
        type: 'RollingUpdate',
        rollingUpdate: {
          maxUnavailable: 1,
        },
      },
      replicas: $._config.replicas,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: { labels: $._config.commonLabels },
        spec: {
          serviceAccountName: $.serviceAccount.metadata.name,
          affinity: podantiaffinity($._config.name),
          containers: [c],
          dnsPolicy: 'Default',
          volumes: [{
            name: 'corefile',
            configMap: {
              name: $.config.metadata.name,
              items: [{
                key: 'Corefile',
                path: 'Corefile',
              }],
            },
          }],
        },
      },
    },
  },
}
