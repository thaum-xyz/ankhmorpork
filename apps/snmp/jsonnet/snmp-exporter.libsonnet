// TODO(paulfantom): consider moving this as a component into kube-prometheus

local defaults = {
  local defaults = self,
  name: 'snmp-exporter',
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
  configData: error 'must provide configData',
};

function(params) {
  _config:: defaults + params,
  metadata:: {
    labels: $._config.commonLabels,
    name: $._config.name,
    namespace: $._config.namespace,
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
        name: 'http',
        port: 9116,
        protocol: 'TCP',
        targetPort: 'http',
      }],
      selector: $._config.selectorLabels,
    },
  },

  configmap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: $.metadata,
    data: {
      'snmp.yaml': $._config.configData,
    },
  },

  local c = {
    name: $._config.name,
    image: $._config.image,

    ports: [{
      containerPort: 9116,
      name: 'http',
    }],
    resources: $._config.resources,
  },

  deployment: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      args: ['--config.file=/config/snmp.yaml'],
      ports: [{
        containerPort: 9116,
        name: 'http',
      }],
      volumeMounts: [{
        mountPath: '/config/snmp.yaml',
        name: 'config',
        subPath: 'snmp.yaml',
      }],
      resources: $._config.resources,
      securityContext: {
        runAsNonRoot: true,
        runAsUser: 1000,
        readOnlyRootFilesystem: true,
      },
      livenessProbe: {
        httpGet: {
          path: '/health',
          port: 'http',
        },
      },
      readinessProbe: {
        httpGet: {
          path: '/health',
          port: 'http',
        },
      },
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: $._config.name,
      namespace: $._config.namespace,
      labels: $._config.commonLabels,
    },
    spec: {
      replicas: $._config.replicas,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          annotations: {
            'checksum.config/md5': std.md5($._config.configData),
          },
          labels: $._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          volumes: [{
            name: 'config',
            configMap: {
              name: $.configmap.metadata.name,
            },
          }],
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
        matchLabels: $._config.selectorLabels,
      },
      endpoints: [
        { port: 'http' },
      ],
    },
  },
}
