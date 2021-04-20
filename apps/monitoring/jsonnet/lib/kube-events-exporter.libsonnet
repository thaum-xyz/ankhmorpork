// TODO(paulfantom): consider moving this into https://github.com/rhobs/kube-events-exporter/tree/master/jsonnet/kube-events-exporter
// and adding as addon in kube-prometheus
// ping @dgrisonnet for opinion

local defaults = {
  local defaults = self,
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  name: 'kube-events-exporter',

  eventTypes: [],
  involvedObjectAPIGroups: [],
  involvedObjectNamespaces: [],
  reportingControllers: [],

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
    metadata: $.metadata,
  },

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: $.metadata,
    rules: [{
      apiGroups: [''],
      resources: ['events'],
      verbs: ['list', 'watch'],
    }],
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
      namespace: $.config.namespace,
    }],
  },

  local kee = {
    args: [] +
          ['--event-types=' + evType for evType in $.config.eventTypes] +
          ['--involved-object-api-groups=' + apiGroup for apiGroup in $.config.involvedObjectAPIGroups] +
          ['--involved-object-namespaces=' + ns for ns in $.config.involvedObjectNamespaces] +
          ['--reporting-controllers=' + controller for controller in $.config.reportingControllers],
    name: $.config.name,
    image: $.config.image,
    ports: [
      { containerPort: 8080, name: 'event' },
      { containerPort: 8081, name: 'exporter' },
    ],
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
          containers: [kee],
          securityContext: {
            runAsNonRoot: true,
            runAsUser: 65534,
          },
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
        { port: 'event' },
        { port: 'exporter' },
      ],
      selector: {
        matchLabels: $.config.selectorLabels,
      },
    },
  },


}
