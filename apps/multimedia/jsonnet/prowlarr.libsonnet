local defaults = {
  local defaults = self,
  name: 'prowlarr',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {},
  commonLabels:: {
    'app.kubernetes.io/name': 'prowlarr',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'prowlarr',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  storage: {
    name: 'prowlarr-config',
    pvcSpec: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '1Gi',
        },
      },
    },
  },
};

function(params) {
  local j = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject($._config.resources),

  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: $._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [{
        name: $.deployment.spec.template.spec.containers[0].ports[0].name,
        targetPort: $.deployment.spec.template.spec.containers[0].ports[0].name,
        port: $.deployment.spec.template.spec.containers[0].ports[0].containerPort,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  pvc: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: $._config.storage.name,
    },
    spec: $._config.storage.pvcSpec,
  },

  deployment: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'TZ',
        value: 'UTC',
      }],
      ports: [{
        containerPort: 9696,
        name: 'http',
      }],
      readinessProbe: {
        tcpSocket: { port: c.ports[0].containerPort },
        initialDelaySeconds: 0,
        periodSeconds: 60,
        failureThreshold: 3,
        timeoutSeconds: 1,
      },
      startupProbe: {
        tcpSocket: { port: c.ports[0].containerPort },
        initialDelaySeconds: 0,
        periodSeconds: 5,
        failureThreshold: 30,
        timeoutSeconds: 1,
      },
      volumeMounts: [
        {
          mountPath: '/config',
          name: 'config',
        },
      ],
      resources: $._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      strategy: { type: 'Recreate' },
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          labels: $._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          volumes: [
            {
              name: 'config',
              persistentVolumeClaim: {
                claimName: $.pvc.metadata.name,
              },
            },
          ],
        },
      },
    },
  },
}
