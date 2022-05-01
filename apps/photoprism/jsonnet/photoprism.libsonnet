local defaults = {
  local defaults = self,
  name: 'photoprism',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '100m', memory: '300Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'photoprism',
    'app.kubernetes.io/version': defaults.version,
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  domain: '',
  envs: {
    TZ: 'UTC',
    PHOTOPRISM_PUBLIC: 'false',
  },
  credentials: {
    admin: '',
    database: '',
  },
  storageSpec: {
    // storageClassName: 'local-path',
    accessModes: ['ReadWriteOnce'],
    resources: {
      requests: {
        storage: '2Gi',
      },
    },
  },
  additionalPVCs: {},
  // additionalPVCs: {
  //   originals: {},
  //   imports: {},
  //   exports: {},
  //   cache: {},
  // },
};

function(params) {
  _config:: defaults + params + {
    [if std.objectHas(params, 'envs') && std.length(params.envs) > 0 then 'envs']: defaults.envs + params.envs,
  },
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  // Safety check
  assert std.isObject($._config.resources),

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
        name: $.statefulSet.spec.template.spec.containers[0].ports[0].name,
        targetPort: $.statefulSet.spec.template.spec.containers[0].ports[0].name,
        port: $.statefulSet.spec.template.spec.containers[0].ports[0].containerPort,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  config: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: $._metadata {
      name: 'config',
    },
    data: $._config.envs,
  },

  credentials: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: $._metadata {
      name: 'credentials',
    },
    data: {
      PHOTOPRISM_ADMIN_PASSWORD: $._config.credentials.admin,
      PHOTOPRISM_DATABASE_PASSWORD: $._config.credentials.database,
    },
  },

  statefulSet: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      envFrom: [
        {
          secretRef: {
            name: $.credentials.metadata.name,
          },
        },
        {
          configMapRef: {
            name: $.config.metadata.name,
          },
        },
      ],
      ports: [{
        containerPort: 2342,
        name: 'http',
      }],
      readinessProbe: {
        httpGet: {
          path: '/api/v1/status',
          port: 'http',
        },
      },
      securityContext: {
        privileged: false,
      },
      volumeMounts: [{
        mountPath: '/photoprism/storage',
        name: 'storage',
      }] + (
        if std.objectHas(params, 'additionalPVCs') then
          [
            {
              name: dir,
              mountPath: params.additionalPVCs[dir].mountPath,
            }
            for dir in std.objectFields(params.additionalPVCs)
          ]
        else []
      ),
      resources: $._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: $._metadata,
    spec: {
      serviceName: $.service.metadata.name,
      replicas: 1,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          labels: $._config.commonLabels,
          annotations: {
            'kubectl.kubernetes.io/default-container': c.name,
            'checksum.config/md5': std.md5(std.toString($.config.data)),
          },
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          [if std.objectHas(params, 'additionalPVCs') then 'volumes']: [
            {
              name: dir,
              persistentVolumeClaim: {
                name: params.additionalPVCs[dir].name,
              },
            }
            for dir in std.objectFields(params.additionalPVCs)
          ],
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: 'storage',
        },
        spec: $._config.storageSpec,
      }],
    },
  },

  [if std.objectHas(params, 'additionalPVCs') then 'additionalPVCs']: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaimList',
    metadata: $._metadata,
    items: [
      {
        apiVersion: 'v1',
        kind: 'PersistentVolumeClaim',
        metadata: $._metadata {
          name: params.additionalPVCs[dir].name,
        },
        spec: params.additionalPVCs[dir].spec,
      }
      for dir in std.objectFields(params.additionalPVCs)
    ],
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
        secretName: $._config.name + '-tls',
        hosts: [$._config.domain],
      }],
      rules: [{
        host: $._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: $._config.name,
                port: {
                  name: $.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },
}
