local defaults = {
  local defaults = self,
  name: 'jackett',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { memory: '120M' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'jackett',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'jackett',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  storage: {
    name: 'jackett-config',
    pvcSpec: {
      storageClassName: 'local-path',
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '2Gi',
        },
      },
    },
  },
};

function(params) {
  local j = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(j._config.resources),

  _metadata:: {
    name: j._config.name,
    namespace: j._config.namespace,
    labels: j._config.commonLabels,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: j._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: j._metadata,
    spec: {
      ports: [{
        name: j.deployment.spec.template.spec.containers[0].ports[0].name,
        targetPort: j.deployment.spec.template.spec.containers[0].ports[0].name,
        port: j.deployment.spec.template.spec.containers[0].ports[0].containerPort,
      }],
      selector: j._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  pvc: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: j._metadata {
      name: j._config.storage.name,
    },
    spec: j._config.storage.pvcSpec,
  },

  deployment: {
    local c = {
      name: j._config.name,
      image: j._config.image,
      imagePullPolicy: 'IfNotPresent',
      ports: [{
        containerPort: 9117,
        name: 'http',
      }],
      livenessProbe: {
        tcpSocket: { port: c.ports[0].containerPort },
        initialDelaySeconds: 30,
        periodSeconds: 60,
        timeoutSeconds: 5,
      },
      volumeMounts: [
        {
          mountPath: '/config',
          name: 'config',
        },
      ],
      resources: j._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: j._metadata,
    spec: {
      replicas: 1,
      strategy: { type: 'Recreate' },
      selector: { matchLabels: j._config.selectorLabels },
      template: {
        metadata: {
          labels: j._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: j.serviceAccount.metadata.name,
          volumes: [
            {
              name: 'config',
              persistentVolumeClaim: {
                claimName: j.pvc.metadata.name,
              },
            },
          ],
          securityContext: {
            // runAsUser: 1000
            // runAsGroup: 1000
            fsGroup: 1000,
          },
        },
      },
    },
  },
}
