// Generic exporter library
// Application CLI arguments are passed via `args` option
// Environment variables are passed from k8s Secret if `secretRefName` is specified. Secret needs to be creted by user.
// Monitoring is enabled via PodMonitor

local defaults = {
  local defaults = self,
  name: error 'must provide name',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  port: error 'must provide port',

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
  replicas: 1,
  secretRefName: null,
  args: [],
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
    metadata: $.metadata,
  },

  local exporter = {
    args: $.config.args,
    [if $.config.secretRefName != null then 'envFrom']: [{ secretRef: { name: $.config.secretRefName } }],
    name: $.config.name,
    image: $.config.image,
    ports: [{
      containerPort: $.config.port,
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
    resources: $.config.resources,
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $.metadata,
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
          containers: [exporter],
          serviceAccountName: $.serviceAccount.metadata.name,
        },
      },
    },
  },

  podMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PodMonitor',
    metadata: $.metadata,
    spec: {
      podMetricsEndpoints: [
        { port: 'http', interval: '30s' },
      ],
      selector: {
        matchLabels: $.config.selectorLabels,
      },
    },
  },

}
