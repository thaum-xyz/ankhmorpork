local timescaledb = import 'github.com/thaum-xyz/jsonnet-libs/apps/timescaledb/timescaledb.libsonnet';
local paperless = import 'paperless.libsonnet';
local redis = import 'redis.libsonnet';
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = {
  web: paperless(config.paperless) + {
    database+:: {},
    databaseEnc: sealedsecret(
      $.web.database.metadata,
      {
        PAPERLESS_DBUSER: config.paperless.database.encryptedUser,
        PAPERLESS_DBPASS: config.paperless.database.encryptedPass,
      }
    ) + {
      spec+: {
        template+: {
          data+: {
            PAPERLESS_DBHOST: 'db.paperless.svc',
            PAPERLESS_DBNAME: config.paperless.database.name,
            PAPERLESS_DBPORT: '5432',
            PAPERLESS_DBSSLMODE: 'prefer',
          }
        }
      }
    },
    secrets+:: {},
    secretsEnc: sealedsecret(
      $.web.secrets.metadata,
      {
        PAPERLESS_ADMIN_USER: config.paperless.secrets.user,
        PAPERLESS_ADMIN_PASSWORD: config.paperless.secrets.pass,
        PAPERLESS_ADMIN_MAIL: config.paperless.secrets.email,
        PAPERLESS_SECRET_KEY: config.paperless.secrets.key,
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
  db: timescaledb(config.db) + {
    credentials: sealedsecret(
      {
        name: 'db',
        namespace: config.db.namespace,
      },
      {
        POSTGRES_USER: config.db.database.encryptedUser,
        POSTGRES_PASSWORD: config.db.database.encryptedPass,
      }
    ),
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
