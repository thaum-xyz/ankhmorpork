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
  local dns = self,
  _config:: defaults + params,
  metadata:: {
    name: dns._config.name,
    namespace: dns._config.namespace,
    labels: dns._config.commonLabels,
  },

  mixin:: (import 'github.com/povilasv/coredns-mixin/mixin.libsonnet') +
          (import 'github.com/kubernetes-monitoring/kubernetes-mixin/alerts/add-runbook-links.libsonnet') {
            _config+:: dns._config.mixin._config,
          },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: dns.metadata {
      labels: dns._config.mixin.ruleLabels + dns.metadata.labels,
    },
    spec: {
      local r = if std.objectHasAll(dns.mixin, 'prometheusRules') then dns.mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll(dns.mixin, 'prometheusAlerts') then dns.mixin.prometheusAlerts.groups else [],
      groups: a + r,
    },
  },

  dashboardCM: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: dns.metadata {
      name: dns.metadata.name + '-dashboards',
      labels+: {
        grafana: 'dashboard',
      },
    },
    //TODO: Fix this to loop over objects
    //data: dns.mixin.grafanaDashboards,
    data: {
      'coredns.json': std.toString(dns.mixin.grafanaDashboards['coredns.json']),
    },
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: dns.metadata,
  },

  // TODO: Converge into one Service object when k8s LoadBalancer will allow to share UDP and TCP protocols
  serviceTCP: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: dns.metadata { name: dns._config.name + '-tcp' },
    spec: {
      type: 'LoadBalancer',
      loadBalancerIP: dns._config.loadBalancerIP,
      ports: [{
        name: 'dns-tcp',
        targetPort: 'dns-tcp',
        port: 53,
        protocol: 'TCP',
      }],
      selector: dns._config.selectorLabels,
    },
  },

  serviceUDP: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: dns.metadata { name: dns._config.name + '-udp' },
    spec: {
      type: 'LoadBalancer',
      loadBalancerIP: dns._config.loadBalancerIP,
      ports: [{
        name: 'dns-udp',
        targetPort: 'dns-udp',
        port: 53,
        protocol: 'UDP',
      }],
      selector: dns._config.selectorLabels,
    },
  },

  // Since DNS Service would be of NodePort of Loadbalancer type it doesn't make sense to create Service just for ServiceMonitor
  podMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PodMonitor',
    metadata: dns.metadata,
    spec: {
      podMetricsEndpoints: [{
        port: 'metrics',
        interval: '30s',
      }],
      selector: {
        matchLabels: dns._config.selectorLabels,
      },
    },
  },

  podDisruptionBudget: {
    apiVersion: 'policy/v1beta1',
    kind: 'PodDisruptionBudget',
    metadata: dns.metadata,
    spec: {
      minAvailable: 1,
      selector: {
        matchLabels: dns._config.selectorLabels,
      },
    },
  },

  config: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: dns.metadata {
      name: dns._config.name + '-corefile',
    },
    data: {
      Corefile: dns._config.corefile,
      //Corefile: 'ok',
    },
  },

  local c = {
    name: dns._config.name,
    image: dns._config.image,
    imagePullPolicy: 'Always',
    resources: dns._config.resources,
    args: ['-conf', '/etc/coredns/Corefile'],
    [if dns._config.secretName != '' then 'envFrom']: [
      {
        secretRef: {
          name: dns._config.secretName,
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
    metadata: dns.metadata,
    spec: {
      strategy: {
        type: 'RollingUpdate',
        rollingUpdate: {
          maxUnavailable: 1,
        },
      },
      replicas: dns._config.replicas,
      selector: { matchLabels: dns._config.selectorLabels },
      template: {
        metadata: { labels: dns._config.commonLabels },
        spec: {
          serviceAccountName: dns.serviceAccount.metadata.name,
          affinity: (import '../../../lib/podantiaffinity.libsonnet').podantiaffinity(dns._config.name),
          containers: [c],
          dnsPolicy: 'Default',
          volumes: [{
            name: 'corefile',
            configMap: {
              name: dns.config.metadata.name,
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
