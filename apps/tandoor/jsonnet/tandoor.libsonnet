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
    statefulSet:: {},
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
                alias /static/;
              }
              # serve media files
              location /media/ {
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
    deployment:: {},
  },
}
