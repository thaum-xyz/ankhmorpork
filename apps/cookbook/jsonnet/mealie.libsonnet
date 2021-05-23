local defaults = {
  local defaults = self,
  name: 'mealie',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  credentialsSecretRef: error 'must provide credentials Secret name',
  resources: {
    requests: { cpu: '90m', memory: '150Mi' },
    limits: { cpu: '200m', memory: '300Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'mealie',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'mealie',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  domain: '',
  // TODO: Make pvcSpec generic
  pvcSpec: {
    storageClassName: 'local-path',
    accessModes: ['ReadWriteOnce'],
    resources: {
      requests: {
        storage: '1Gi',
      },
    },
  },
};

function(params) {
  local m = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(m._config.resources),

  _metadata:: {
    name: m._config.name,
    namespace: m._config.namespace,
    labels: m._config.commonLabels,
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
        targetPort: m.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 80,
      }],
      selector: m._config.selectorLabels,
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
      name: m._config.name,
      image: m._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'DB_TYPE',
        value: 'sqlite',
      }],
      envFrom: [{
        secretRef: {
          name: m._config.credentialsSecretRef,
        },
      }],
      ports: [{
        containerPort: 80,
        name: 'http',
      }],
      volumeMounts: [{
        mountPath: '/app/data',
        name: 'appdata',
      }],
      resources: m._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      selector: { matchLabels: m._config.selectorLabels },
      template: {
        metadata: {
          labels: m._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: m.serviceAccount.metadata.name,
          volumes: [{
            name: 'appdata',
            persistentVolumeClaim: {
              claimName: m.pvc.metadata.name,
            },
          }],
        },
      },
    },
  },

  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: m._config.name + '-tls',
        hosts: [m._config.domain],
      }],
      rules: [{
        host: m._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: m._config.name,
                port: {
                  name: m.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },
}
