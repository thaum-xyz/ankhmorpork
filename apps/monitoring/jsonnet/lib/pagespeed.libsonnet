// Library for pagespeed/lighthouse exporter
// Monitoring is enabled via Probe

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
  sites: [],
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

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $.metadata,
    spec: {
      ports: [{
        name: 'http',
        port: 9271,
        targetPort: 'http',
      }],
      selector: $.config.selectorLabels,
    },
  },

  local exporter = {
    args: $.config.args,
    name: $.config.name,
    image: $.config.image,
    ports: [{
      containerPort: 9271,
      name: 'http',
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
          containers: [exporter],
          serviceAccountName: $.serviceAccount.metadata.name,
        },
      },
    },
  },

  probe: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'Probe',
    metadata: $.metadata,
    spec: {
      interval: '5m',
      scrapeTimeout: '3m',
      prober: {
        url: $.service.metadata.name + '.' + $.config.namespace + '.svc:9271',
      },
      targets: {
        staticConfig: {
          static: $.config.sites,
        },
      },
    },
  },
}
