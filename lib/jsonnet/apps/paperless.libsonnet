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
    #'app.kubernetes.io/part-of': 'paperless',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  ingress: {
    domain: '',
    className: 'nginx',
    annotations: {},
  },
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
    PAPERLESS_CONSUMER_POLLING: '60',  // This is required for NFS storage types
    PAPERLESS_CONSUMER_POLLING_RETRY_COUNT: '10',
    PAPERLESS_CONSUMER_POLLING_DELAY: '30',
    PAPERLESS_TASK_WORKERS: '1',  // Related to https://github.com/paperless-ngx/paperless-ngx/issues/1098
    PAPERLESS_WEBSERVER_WORKERS: '1',  // Related to https://github.com/paperless-ngx/paperless-ngx/issues/1098
    PAPERLESS_ENABLE_FLOWER: 'true',  // Enable celery monitoring
  },
  secrets: {
    user: '',
    pass: '',
    email: '',
    key: '',
  },
  backupSchedule: '0 0 * * *',
  storage: {
    data: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '2Gi',
        },
      },
    },
    media: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '2Gi',
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
    backups: {
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
    domain: defaults.ingress.domain + params.ingress.domain,
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
      PAPERLESS_URL: 'https://' + $._config.ingress.domain,
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
  pvcBackups: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: 'backups',
      labels: $._config.commonLabels {
        'app.kubernetes.io/component': 'backup',
      },
    },
    spec: $._config.storage.backups,
  },

  local c = {
    name: $._config.name,
    image: $._config.image,
    ports: [
      {
        containerPort: 8000,
        name: 'http',
      },
      {
        containerPort: 5555,
        name: 'metrics',
      },
    ],
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
    readinessProbe: {
      initialDelaySeconds: 15,
      periodSeconds: 5,
      httpGet: {
        path: '/accounts/login/?next=/',
        port: 'http',
      },
    },
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

  statefulSet: {
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
                claimName: $.pvcData.metadata.name,
              },
            },
            {
              name: 'media',
              persistentVolumeClaim: {
                claimName: $.pvcMedia.metadata.name,
              },
            },
            {
              name: 'consume',
              persistentVolumeClaim: {
                claimName: $.pvcConsume.metadata.name,
              },
            },
          ],
        },
      },
    },
  },

  cronjob: {
    apiVersion: 'batch/v1',
    kind: 'CronJob',
    metadata: $._metadata {
      name: $._metadata.name + '-backup',
      labels+: {
        'app.kubernetes.io/component': 'backup',
      },
    },
    spec: {
      concurrencyPolicy: 'Forbid',
      failedJobsHistoryLimit: 2,
      schedule: $._config.backupSchedule,
      successfulJobsHistoryLimit: 1,
      jobTemplate: {
        spec: {
          template: {
            metadata: {
              labels: $._config.commonLabels {
                'app.kubernetes.io/component': 'backup',
              },
            },
            spec: {
              containers: [c {
                env: [],
                command: ["/usr/local/bin/document_exporter"],
                args: [
                  "--use-folder-prefix",
                  "--zip",
                  "--no-color",
                  "--skip-checks",
                  "/mnt/backups",
                ],
                name: "backup",
                ports: [],
                resources: {},
                readinessProbe:: {},
                volumeMounts+: [
                  {
                    mountPath: '/mnt/backups',
                    name: 'backups',
                  },
                ],
              }],
              restartPolicy: 'Never',
              serviceAccountName: $.serviceAccount.metadata.name,
              volumes: [
                {
                  name: 'data',
                  persistentVolumeClaim: {
                    claimName: $.pvcData.metadata.name,
                  },
                },
                {
                  name: 'media',
                  persistentVolumeClaim: {
                    claimName: $.pvcMedia.metadata.name,
                  },
                },
                {
                  name: 'consume',
                  persistentVolumeClaim: {
                    claimName: $.pvcConsume.metadata.name,
                  },
                },
                {
                  name: 'backups',
                  persistentVolumeClaim: {
                    claimName: $.pvcBackups.metadata.name,
                  },
                },
              ],
            },
          },
        },
      },
    },
  },

  podMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PodMonitor',
    metadata: $._metadata,
    spec: {
      selector: {
        matchLabels: $._config.selectorLabels,
      },
      podMetricsEndpoints: [{
        port: 'metrics',
        interval: '30s',
        path: '/metrics',
        scheme: 'http',
      }],
    },
  },

  prometheusRules: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata,
    spec: {
      groups: [
        {
          name: 'paperless.rules',
          rules: [
            {
              alert: 'PaperlessUnhealthy',
              expr: 'up{job="paperless"} == 0',
              'for': '5m',
              labels: {
                severity: 'critical',
              },
              annotations: {
                summary: 'Paperless is unhealthy',
                description: 'Paperless has been unhealthy for more than 5 minutes.',
              },
            },
            {
              alert: 'CeleryWorkerOffline',
              expr: 'flower_worker_online == 0',
              'for': '2m',
              labels: {
                context: 'celery-worker',
                severity: 'warning',
              },
              annotations: {
                description: 'Celery worker {{ $labels.worker }} has been offline for more than 2 minutes.',
                summary: 'Celery worker offline',
              },
            },
            {
              alert: 'TaskFailureRatioTooHigh',
              expr: 'sum(rate(flower_events_total{namespace="paperless",type="task-failed"}[15m])) > 0',
              labels: {
                context: 'celery-task',
                severity: 'warning',
              },
              annotations: {
                description: 'Average task failure ratio for task {{ $labels.task }} is {{ $value }}.',
                summary: 'Task Failure Ratio High.',
              },
            },
            {
              alert: 'TaskPrefetchTimeTooHigh',
              expr: 'sum(avg_over_time(flower_task_prefetch_time_seconds[15m])) by (task, worker) > 1',
              'for': '5m',
              labels: {
                context: 'celery-task',
                severity: 'warning',
              },
              annotations: {
                description: 'Average task prefetch time at worker for task {{ $labels.task }} and worker {{ $labels.worker }} is {{ $value }}.',
                summary: 'Average Task Prefetch Time Too High.',
              },
            },
          ],
        },
      ],
    },
  },

  [if std.objectHas(params, 'ingress') && std.objectHas(params.ingress, 'domain') && std.length(params.ingress.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: $._config.ingress.annotations,
    },
    spec: {
      ingressClassName: $._config.ingress.className,
      tls: [{
        secretName: $._config.name + '-tls',
        hosts: [$._config.ingress.domain],
      }],
      rules: [{
        host: $._config.ingress.domain,
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
