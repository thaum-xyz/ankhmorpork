local defaults = {
  local defaults = self,
  name: 'externalhosts',
  namespace: error 'must provide namespace',
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/component': 'endpoint',
  },
  addresses: [],
  port: 80,
  interval: '30s',
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  endpoints: {
    apiVersion: 'v1',
    kind: 'Endpoints',
    metadata: $._metadata,
    subsets: [{
      addresses: [
        { ip: address }
        for address in $._config.addresses
      ],
      ports: [{
        port: $._config.port,
        name: 'http',
      }],
    }],
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      clusterIP: 'None',
      ports: $.endpoints.subsets[0].ports,
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: [{
        interval: $._config.interval,
        port: $.endpoints.subsets[0].ports[0].name,
      }],
      selector: {
        matchLabels: $.service.metadata.labels,
      },
    },
  },
}
