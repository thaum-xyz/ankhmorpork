local paperless = import 'apps/paperless.libsonnet';
local timescaledb = import 'apps/timescaledb.libsonnet';
local redis = import 'redis.libsonnet';
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = {
  web: paperless(config.paperless) + {
    database+:: {},
    databaseSecret: externalsecret(
      $.web.database.metadata,
      'doppler-auth-api',
      {
        PAPERLESS_DBUSER: config.paperless.database.userRef,
        PAPERLESS_DBPASS: config.paperless.database.passRef,
      }
    ) + {
      spec+: {
        target+: {
          template+: {
            engineVersion: 'v2',
            data+: {
              PAPERLESS_DBUSER: '{{ .PAPERLESS_DBUSER }}',
              PAPERLESS_DBPASS: '{{ .PAPERLESS_DBPASS }}',
              PAPERLESS_DBHOST: 'postgres-rw.paperless.svc',
              PAPERLESS_DBNAME: config.paperless.database.name,
              PAPERLESS_DBPORT: '5432',
              PAPERLESS_DBSSLMODE: 'prefer',
            },
          },
        },
      },
    },
    secrets+:: {},
    secretsExternal: externalsecret(
      $.web.secrets.metadata,
      'doppler-auth-api',
      {
        PAPERLESS_ADMIN_USER: config.paperless.secretsRefs.user,
        PAPERLESS_ADMIN_PASSWORD: config.paperless.secretsRefs.pass,
        PAPERLESS_ADMIN_MAIL: config.paperless.secretsRefs.email,
        PAPERLESS_SECRET_KEY: config.paperless.secretsRefs.key,
      }
    ),

    pvConsume: {
      apiVersion: 'v1',
      kind: 'PersistentVolume',
      metadata: $.web.pvcConsume.metadata,
      spec: {
        accessModes: ['ReadWriteOnce'],
        capacity: {
          storage: '4Gi',
        },
        nfs: {
          path: '/Paperless',
          server: '192.168.2.29',
        },
        persistentVolumeReclaimPolicy: 'Retain',
        storageClassName: 'manual',
        volumeMode: 'Filesystem',
      },
    },

    ingress+: {
      metadata+: {
        labels+: {
          probe: 'enabled',
        },
      },
    },

    statefulSet+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: {
              'kubernetes.io/arch': 'amd64',
            },
          },
        },
      },
    },
  },
  db: {
    credentialsUser: externalsecret(
      {
        name: 'pg-user',
        namespace: config.db.namespace,
      },
      'doppler-auth-api',
      {
        username: config.db.database.userRef,
        password: config.db.database.passRef,
      }
    ) + {
      spec+: {
        target+: {
          template+: {
            type: 'kubernetes.io/basic-auth',
          },
        },
      },
    },
    credentialsAdmin: externalsecret(
      {
        name: 'pg-admin',
        namespace: config.db.namespace,
      },
      'doppler-auth-api',
      {
        password: config.db.database.adminPassRef,
      }
    ) + {
      spec+: {
        target+: {
          template+: {
            type: 'kubernetes.io/basic-auth',
            data: {
              username: 'postgres',
              password: '{{ .password }}',
            },
          },
        },
      },
    },
    cluster: {
      apiVersion: 'postgresql.cnpg.io/v1',
      kind: 'Cluster',
      metadata: {
        name: 'postgres',
        namespace: config.db.namespace,
      },
      spec: {
        instances: 1,
        monitoring: {
          enablePodMonitor: true,
        },
        superuserSecret: {
          name: $.db.credentialsAdmin.metadata.name,
        },
        bootstrap: {
          initdb: {
            database: config.db.database.name,
            owner: config.db.database.user,
            secret: {
              name: $.db.credentialsUser.metadata.name,
            },
          },
        },
        resources: config.db.resources,
        storage: {
          storageClass: config.db.storage.pvcSpec.storageClassName,
          size: config.db.storage.pvcSpec.resources.requests.storage,
        },
      },
    },
  },
  broker: redis(config.broker {
    commonLabels+:: {
      'app.kubernetes.io/component': 'broker',
    },
  }),

};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
