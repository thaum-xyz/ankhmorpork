local defaults = {
  local defaults = self,
  name: 'paperless',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '50m', memory: '70Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'webservice',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  domain: '',
  timezone: 'Europe/Berlin',
  database: {
    port: '5432',
    sslmode: 'prefer',
    user: '',
    pass: '',
  },
  broker: {
    address: 'redis://redis.paperless.svc:6379',
  },
  config: {
    PAPERLESS_FILENAME_FORMAT: '{created_year}/{correspondent}/{asn} - {title}',
    PAPERLESS_CONSUMER_POLLING: '30',  // This is required for NFS storage types
    PAPERLESS_TASK_WORKERS: '1',  // Related to https://github.com/paperless-ngx/paperless-ngx/issues/1098
    PAPERLESS_WEBSERVER_WORKERS: '1',  // Related to https://github.com/paperless-ngx/paperless-ngx/issues/1098
  },
  secrets: {
    user: '',
    pass: '',
    email: '',
    key: '',
  },
  storage: {
    data: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '1Gi',
        },
      },
    },
    media: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '10Gi',
        },
      },
    },
    consume: {
      storageClassName: 'manual',
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '10Gi',
        },
      },
    },
  },
};

function(params) {
  _config:: defaults + params + {
    config: defaults.config + params.config,
    database: defaults.database {
      name: params.name,
      host: 'db.%s.svc' % params.namespace,
    } + params.database,
  },

  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  // Safety check
  assert std.isObject($._config.resources),
  assert std.isObject($._config.storage.data),
  assert std.isObject($._config.storage.media),
  assert std.isObject($._config.storage.consume),

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
      name: $._config.name + '-config',
    },
    data: $._config.config {
      PAPERLESS_URL: 'https://' + $._config.domain,
      PAPERLESS_REDIS: $._config.broker.address,
      PAPERLESS_TIME_ZONE: $._config.timezone,
      PAPERLESS_CORS_ALLOWED_HOSTS: 'http://%(name)s.%(namespace)s.svc,https://%(domain)s' % $._config,
    },
  },

  secrets: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: $._metadata {
      name: $._config.name + '-secrets',
    },
    data: {
      PAPERLESS_ADMIN_USER: $._config.secrets.user,
      PAPERLESS_ADMIN_PASSWORD: $._config.secrets.pass,
      PAPERLESS_ADMIN_MAIL: $._config.secrets.email,
      PAPERLESS_SECRET_KEY: $._config.secrets.key,
    },
  },

  database: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: $._metadata {
      name: $._config.name + '-db',
    },
    data: {
      PAPERLESS_DBSSLMODE: $._config.database.sslmode,
      PAPERLESS_DBHOST: $._config.database.host,
      PAPERLESS_DBPORT: $._config.database.port,
      PAPERLESS_DBNAME: $._config.database.name,
      PAPERLESS_DBUSER: $._config.database.user,
      PAPERLESS_DBPASS: $._config.database.pass,
    },
  },

  // TODO: Create PodSecurityPolicy
  psp:: {},

  // TODO: Create NetworkPolicy
  NetworkPolicy:: {},

  // TODO: Make PVCList out of those
  pvcData: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: 'data',
    },
    spec: $._config.storage.data,
  },
  pvcMedia: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: 'media',
    },
    spec: $._config.storage.media,
  },
  pvcConsume: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: 'consume',
    },
    spec: $._config.storage.consume,
  },

  statefulSet: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      ports: [{
        containerPort: 8000,
        name: 'http',
      }],
      envFrom: [
        { configMapRef: { name: $.config.metadata.name } },
        { secretRef: { name: $.secrets.metadata.name } },
        { secretRef: { name: $.database.metadata.name } },
      ],
      env: [
        {
          // Adding POD IP to Allowed hosts
          // From https://github.com/korfuri/django-prometheus/issues/81#issuecomment-456210855
          name: 'POD_IP',
          valueFrom: {
            fieldRef: {
              fieldPath: 'status.podIP',
            },
          },
        },
        {
          name: 'PAPERLESS_ALLOWED_HOSTS',
          value: $._config.name + '.' + $._config.namespace + '.svc,$(POD_IP)',
        },
      ],
      securityContext: {
        privileged: false,
      },
      volumeMounts: [
        {
          mountPath: '/usr/src/paperless/data',
          name: 'data',
        },
        {
          mountPath: '/usr/src/paperless/media',
          name: 'media',
        },
        {
          mountPath: '/usr/src/paperless/consume',
          name: 'consume',
        },
      ],
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
            'checksum.config/md5': std.md5(std.manifestJsonMinified($.config.data)),
            'checksum.secrets/md5': std.md5(std.manifestJsonMinified($._config.secrets)),
            'checksum.database/md5': std.md5(std.manifestJsonMinified($._config.database)),
          },
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          volumes: [
            {
              name: 'data',
              persistentVolumeClaim: {
                claimName: 'data',
              },
            },
            {
              name: 'media',
              persistentVolumeClaim: {
                claimName: 'media',
              },
            },
            {
              name: 'consume',
              persistentVolumeClaim: {
                claimName: 'consume',
              },
            },
          ],
        },
      },
    },
  },

  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: {
        'nginx.ingress.kubernetes.io/proxy-body-size': '10m',
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
