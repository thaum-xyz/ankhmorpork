local defaults = {
  local defaults = self,
  name: error 'must provide name',
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
  replicas: 1,
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

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: $.metadata,
    rules: [
      {
        apiGroups: ['sloth.slok.dev'],
        resources: ['*'],
        verbs: ['*'],
      },
      {
        apiGroups: ['monitoring.coreos.com'],
        resources: ['prometheusrules'],
        verbs: ['create', 'list', 'get', 'update', 'watch'],
      },
    ],
  },

  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: $.metadata,
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: $.clusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: $.serviceAccount.metadata.name,
      namespace: $.serviceAccount.metadata.namespace,
    }],
  },

  local container = {
    args: ['kubernetes-controller'],
    name: $.config.name,
    image: $.config.image,
    ports: [{
      containerPort: 8081,
      name: 'metrics',
    }],
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
          containers: [container],
          serviceAccountName: $.serviceAccount.metadata.name,
          nodeSelector: {
            'kubernetes.io/os': 'linux',
          },
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
        { port: 'metrics', interval: '30s' },
      ],
      selector: {
        matchLabels: $.config.selectorLabels,
      },
    },
  },

}
