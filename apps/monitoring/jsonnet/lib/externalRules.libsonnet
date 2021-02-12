local defaults = {
  name: error 'provide name',
  namespace: 'monitoring',
  labels: {
    prometheus: 'k8s',
    role: 'alert-rules',
  },
  groups: error 'provide alert groups',
};

function(params) {
  local cfg = defaults + params + {
    objName: params.name + 'PrometheusRule',
  },

  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    labels: cfg.labels,
    name: cfg.name,
    namespace: cfg.namespace,
  },
  spec: {
    groups: cfg.groups,
  },
}
