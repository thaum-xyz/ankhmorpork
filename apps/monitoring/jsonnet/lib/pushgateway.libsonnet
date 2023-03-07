// TODO(paulfantom): consider moving this as a component into kube-prometheus

local defaults = {
  local defaults = self,
  name: 'pushgateway',
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

  resources: {},
};

function(params) {
  config:: defaults + params,
  metadata:: {
    labels: $.config.commonLabels,
    name: $.config.name,
    namespace: $.config.namespace,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: $.metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $.metadata,
    spec: {
      ports: [{
        name: 'http-push',
        port: 9091,
        protocol: 'TCP',
        targetPort: 'http-push',
      }],
      selector: $.config.selectorLabels,
    },
  },

  local pgw = {
    name: $.config.name,
    image: $.config.image,
    ports: [{
      containerPort: 9091,
      name: 'http-push',
    }],
    resources: $.config.resources,
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $.metadata,
    spec: {
      replicas: 1,
      selector: {
        matchLabels: $.config.selectorLabels,
      },
      template: {
        metadata: {
          labels: $.config.commonLabels,
        },
        spec: {
          containers: [pgw],
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
    metadata: $.metadata,
    spec: {
      selector: {
        matchLabels: $.config.selectorLabels,
      },
      endpoints: [
        { port: 'http-push', interval: '30s', honorLabels: true },
      ],
    },
  },
}
