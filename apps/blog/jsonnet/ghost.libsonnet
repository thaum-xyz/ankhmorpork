local defaults = {
  local defaults = self,
  name: 'ghost',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { memory: '120M' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'ghost',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'ghost',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  domain: error 'must provide domain',
  // TODO: Make pvcSpec generic
  pvcSpec: {
    storageClassName: 'local-path',
    accessModes: ['ReadWriteMany'],
    resources: {
      requests: {
        storage: '2Gi',
      },
    },
  },
};

function(params) {
  local g = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(g._config.resources),

  _metadata:: {
    name: g._config.name,
    namespace: g._config.namespace,
    labels: g._config.commonLabels,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: $._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: g.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 2368,
      }],
      selector: g._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  pvc: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata,
    spec: $._config.pvcSpec,
  },

  deployment: {
    local c = {
      name: g._config.name,
      image: g._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'url',
        value: 'https://' + g._config.domain,
      }],
      ports: [{
        containerPort: 2368,
        name: 'http',
      }],
      livenessProbe: {
        tcpSocket: { port: 2368 },
        initialDelaySeconds: 30,
        periodSeconds: 60,
        timeoutSeconds: 5,
      },
      volumeMounts: [
        {
          mountPath: '/var/lib/ghost/content',
          name: 'content',
        },
        {
          mountPath: '/var/lib/ghost/content/logs',
          name: 'logs',
        },
      ],
      resources: g._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      strategy: { type: 'Recreate' },
      selector: { matchLabels: g._config.selectorLabels },
      template: {
        metadata: {
          labels: g._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: g.serviceAccount.metadata.name,
          volumes: [
            {
              name: 'content',
              persistentVolumeClaim: {
                claimName: g.pvc.metadata.name,
              },
            },
            {
              name: 'logs',
              emptyDir: {},
            },
          ],
        },
      },
    },
  },

  ingress: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
        'nginx.ingress.kubernetes.io/proxy-body-size': '600K',
      },
    },
    spec: {
      tls: [{
        secretName: g._config.name + '-tls',
        hosts: [g._config.domain],
      }],
      rules: [{
        host: g._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: g._config.name,
                port: {
                  name: g.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },
}
