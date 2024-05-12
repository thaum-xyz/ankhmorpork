local defaults = {
  local defaults = self,
  name: 'tandoor',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '120m', memory: '200Mi' },
    //limits: { cpu: '400m', memory: '600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'tandoor',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/part-of': 'tandoor',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  database: {
    name: 'recipes',
    host: 'db.default.svc.cluster.local',
    port: 5432,
    credentialsSecretRef: '',
  },
  ingress: {
    domain: '',
    className: 'nginx',
    metadata: {
      annotations: {},
      labels: {},
    },
  },
  storage: {
    media: {
      storageClassName: '',
      size: '1Gi',
    },
    static: {
      storageClassName: '',
      size: '1Gi',
    },
  },
};

function(params) {
  _config:: defaults + params + {
    database: defaults.database + params.database,
    ingress: defaults.ingress + params.ingress,
    storage: defaults.storage + params.storage,
  },
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  common: {
    pvcMedia: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: $._metadata {
        name: 'media',
      },
      spec: {
        [if std.length($._config.storage.media.storageClassName) > 0 then 'storageClassName']: $._config.storage.media.storageClassName,
        accessModes: ['ReadWriteMany'],
        resources: {
          requests: {
            storage: $._config.storage.media.size,
          },
        },
      },
    },
    pvcStatic: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: $._metadata {
        name: 'static',
      },
      spec: {
        [if std.length($._config.storage.static.storageClassName) > 0 then 'storageClassName']: $._config.storage.static.storageClassName,
        accessModes: ['ReadWriteMany'],
        resources: {
          requests: {
            storage: $._config.storage.static.size,
          },
        },
      },
    },
    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: $._metadata + $._config.ingress.metadata + {
        labels: $._metadata.labels + $._config.ingress.metadata.labels,
        annotations: $._config.ingress.metadata.annotations,
      },
      spec: {
        ingressClassName: $._config.ingress.className,
        rules: [{
          host: $._config.ingress.domain,
          http: {
            paths: [
              {
                backend: {
                  service: {
                    name: $.app.service.metadata.name,
                    port: {
                      name: $.app.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/',
                pathType: 'Prefix',
              },
              {
                backend: {
                  service: {
                    name: $.static.service.metadata.name,
                    port: {
                      name: $.static.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/media',
                pathType: 'Prefix',
              },
              {
                backend: {
                  service: {
                    name: $.static.service.metadata.name,
                    port: {
                      name: $.static.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/static',
                pathType: 'Prefix',
              },
            ],
          },
        }],
        tls: [{
          hosts: [$._config.ingress.domain],
          secretName: $._config.name + '-tls',
        }],
      },
    },
  },

  app: {
    _metadata:: $._metadata {
      _addedLabels:: {
        'app.kubernetes.io/component': 'webapp',
      },
      selectorLabels:: $._config.selectorLabels + $.app._metadata._addedLabels,
      labels+: $.app._metadata._addedLabels,
    },
    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: $.app._metadata,
    },
    config: {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: $.app._metadata {
        name+: '-config-envs',
      },
      data: {
        ALLOWED_HOSTS: '*',
        DB_ENGINE: 'django.db.backends.postgresql_psycopg2',
        DEBUG: '0',
        GUNICORN_MEDIA: '0',
        POSTGRES_DB: $._config.database.name,
        POSTGRES_HOST: $._config.database.host,
        POSTGRES_PORT: std.toString($._config.database.port),
      },
    },
    secretKey: {
      apiVersion: 'v1',
      kind: 'Secret',
      metadata: $.app._metadata {
        name+: '-django',
      },
      stringData: {
        SECRET_KEY: 'changeMe',
      },
    },
    service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: $.app._metadata,
      spec: {
        ports: [{
          name: 'gunicorn',
          port: 8080,
          protocol: 'TCP',
          targetPort: 'gunicorn',
        }],
        selector: $.app._metadata.selectorLabels,
      },
    },
    local tandoor = {
      command: [
        '/opt/recipes/venv/bin/gunicorn',
        '-b',
        ':8080',
        '--access-logfile',
        '-',
        '--error-logfile',
        '-',
        '--log-level',
        'INFO',
        'recipes.wsgi',
      ],
      env: [
        {
          name: 'POSTGRES_USER',
          valueFrom: {
            secretKeyRef: {
              key: 'username',
              name: $._config.database.credentialsSecretRef,
            },
          },
        },
        {
          name: 'POSTGRES_PASSWORD',
          valueFrom: {
            secretKeyRef: {
              key: 'password',
              name: $._config.database.credentialsSecretRef,
            },
          },
        },
      ],
      envFrom: [
        { secretRef: { name: $.app.secretKey.metadata.name } },
        { configMapRef: { name: $.app.config.metadata.name } },
      ],
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      name: 'recipes',
      ports: [{
        containerPort: 8080,
        name: 'gunicorn',
      }],
      readinessProbe: {
        httpGet: {
          path: '/accounts/login/?next=/search/',
          port: "gunicorn",
          scheme: 'HTTP',
        },
        periodSeconds: 30,
        initialDelaySeconds: 15,
      },
      resources: $._config.resources,
      securityContext: {
        runAsUser: 65534,
      },
      volumeMounts: [
        {
          mountPath: '/opt/recipes/mediafiles',
          name: 'media',
          subPath: 'files',
        },
        {
          mountPath: '/opt/recipes/staticfiles',
          name: 'static',
          subPath: 'files',
        },
      ],
    },

    local init = tandoor {
      command: [
        'sh',
        '-c',
        |||
          set -e
          source venv/bin/activate
          echo "Updating database"
          python manage.py migrate
          python manage.py collectstatic_js_reverse
          python manage.py collectstatic --noinput
          echo "Setting media file attributes"
          chown -R 65534:65534 /opt/recipes/mediafiles
          find /opt/recipes/mediafiles -type d | xargs -r chmod 755
          find /opt/recipes/mediafiles -type f | xargs -r chmod 644
          echo "Done"
        |||,
      ],
      name: 'initialize',
      readinessProbe:: {},
      ports:: [],
      securityContext: {
        runAsUser: 0,
      },
    },

    statefulSet: {
      apiVersion: 'apps/v1',
      kind: 'StatefulSet',
      metadata: $.app._metadata,
      spec: {
        replicas: 1,
        selector: {
          matchLabels: $.app._metadata.selectorLabels,
        },
        serviceName: $.app.service.metadata.name,
        updateStrategy: {
          type: 'RollingUpdate',
        },
        template: {
          metadata: {
            labels: $.app._metadata.selectorLabels,
          },
          spec: {
            containers: [tandoor],
            initContainers: [init],
            restartPolicy: 'Always',
            serviceAccountName: $.app.serviceAccount.metadata.name,
            volumes: [
              {
                name: 'media',
                persistentVolumeClaim: {
                  claimName: 'media',
                },
              },
              {
                name: 'static',
                persistentVolumeClaim: {
                  claimName: 'static',
                },
              },
            ],
          },
        },
      },
    },
  },

  static: {
    _metadata:: $._metadata {
      name+: '-static',
      _addedLabels:: {
        'app.kubernetes.io/name': 'nginx',
        'app.kubernetes.io/component': 'static-files-webserver',
      },
      selectorLabels:: $._config.selectorLabels + $.static._metadata._addedLabels,
      labels+: $.static._metadata._addedLabels,
    },
    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: $.static._metadata,
    },
    config: {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: $.static._metadata,
      data: {
        'nginx.conf': |||
          events {
            worker_connections 1024;
          }
          http {
            include mime.types;
            server {
              listen 80;
              server_name _;
              client_max_body_size 16M;
              # serve static files
              location /static/ {
                add_header Cache-Control "max-age=2592000, public";
                alias /static/;
              }
              # serve media files
              location /media/ {
                add_header Cache-Control "max-age=5184000, public";
                alias /media/;
              }
            }
          }
        |||,
      },
    },
    service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: $.static._metadata,
      spec: {
        ports: [{
          name: 'http',
          port: 80,
          protocol: 'TCP',
          targetPort: 'http',
        }],
        selector: $.static._metadata.selectorLabels,
      },
    },
    local nginx = {
      image: 'nginx:latest',
      imagePullPolicy: 'Always',
      name: 'nginx',
      ports: [{
        containerPort: 80,
        name: 'http',
        protocol: 'TCP',
      }],
      resources: {
        requests: {
          cpu: '2m',
          memory: '5Mi',
        },
      },
      volumeMounts: [
        {
          mountPath: '/etc/nginx/nginx.conf',
          name: 'nginx-config',
          readOnly: true,
          subPath: std.objectFields($.static.config.data)[0],
        },
        {
          mountPath: '/media',
          name: 'media',
          subPath: 'files',
          readOnly: true,
        },
        {
          mountPath: '/static',
          name: 'static',
          subPath: 'files',
          readOnly: true,
        },
      ],
    },
    deployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: $.static._metadata,
      spec: {
        selector: {
          matchLabels: $.static._metadata.selectorLabels,
        },
        strategy: {
          type: 'Recreate',
        },
        template: {
          metadata: {
            labels: $.static._metadata.selectorLabels,
          },
          spec: {
            affinity: {
              podAntiAffinity: {
                prefferedDuringSchedulingIgnoredDuringExecution: [{
                  labelSelector: {
                    matchExpressions: [{
                      key: 'app.kubernetes.io/name',
                      operator: 'In',
                      values: [$.static._metadata.labels['app.kubernetes.io/name']],
                    }],
                  },
                  topologyKey: 'kubernetes.io/hostname',
                }],
              },
            },
            containers: [nginx],
            restartPolicy: 'Always',
            serviceAccountName: $.static.serviceAccount.metadata.name,
            volumes: [
              {
                name: 'media',
                persistentVolumeClaim: {
                  claimName: $.common.pvcMedia.metadata.name,
                },
              },
              {
                name: 'static',
                persistentVolumeClaim: {
                  claimName: $.common.pvcStatic.metadata.name,
                },
              },
              {
                configMap: {
                  name: $.static.config.metadata.name,
                },
                name: 'nginx-config',
              },
            ],
          },
        },
      },
    },
  },
}
