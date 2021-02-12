// TODO(paulfantom): consider moving this as an addon into kube-prometheus

local defaults = {
  local defaults = self,
  name: 'smokeping',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',

  commonLabels: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'exporter',
  },

  selectorLabels: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },

  replicas: 1,
  resources: {},
  hosts: [],
};

function(params) {
  config:: defaults + params,

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: $.config.commonLabels,
      name: $.config.name,
      namespace: $.config.namespace,
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      labels: $.config.commonLabels,
      name: $.config.name,
      namespace: $.config.namespace,
    },
    spec: {
      ports: [{
        name: 'http',
        port: 9374,
        protocol: 'TCP',
        targetPort: 'http',
      }],
      selector: $.config.selectorLabels,
    },
  },

  local smoke = {
    name: $.config.name,
    image: $.config.image,
    args: $.config.hosts,
    ports: [{
      containerPort: 9374,
      name: 'http',
    }],
    readinessProbe: {
      tcpSocket: {
        port: 'http',
      },
      initialDelaySeconds: 1,
      failureThreshold: 5,
      timeoutSeconds: 10,
    },
    securityContext: {
      capabilities: {
        add: ['NET_RAW'],
      },
    },
    resources: $.config.resources,
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      labels: $.config.commonLabels,
      name: $.config.name,
      namespace: $.config.namespace,
    },
    spec: {
      replicas: $.config.replicas,
      selector: {
        matchLabels: $.config.selectorLabels,
      },
      template: {
        metadata: {
          labels: $.config.commonLabels,
        },
        spec: {
          containers: [smoke],
          securityContext: {
            runAsNonRoot: true,
            runAsUser: 65534,
          },
          serviceAccountName: $.serviceAccount.metadata.name,
        },
      },
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: $.config.name,
      namespace: $.config.namespace,
      labels: $.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: $.config.selectorLabels,
      },
      endpoints: [
        { port: 'http', interval: '30s' },
      ],
    },
  },
}
