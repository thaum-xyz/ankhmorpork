local timescaledb = import 'github.com/thaum-xyz/jsonnet-libs/apps/timescaledb/timescaledb.libsonnet';
local paperless = import 'paperless.libsonnet';
local redis = import 'redis.libsonnet';
local externalsecret = (import '../../../lib/jsonnet/utils/externalsecrets.libsonnet').externalsecret;

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
        template+: {
          data+: {
            PAPERLESS_DBHOST: 'db.paperless.svc',
            PAPERLESS_DBNAME: config.paperless.database.name,
            PAPERLESS_DBPORT: '5432',
            PAPERLESS_DBSSLMODE: 'prefer',
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
  db: timescaledb(config.db) + {
    credentials: externalsecret(
      {
        name: 'db',
        namespace: config.db.namespace,
      },
      'doppler-auth-api',
      {
        POSTGRES_USER: config.db.database.userRef,
        POSTGRES_PASSWORD: config.db.database.passRef,
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
