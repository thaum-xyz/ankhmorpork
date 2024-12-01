local postgres = import 'apps/cloudnative-pg-cluster.libsonnet';
local paperless = import 'apps/paperless.libsonnet';
local redis = import 'redis.libsonnet';
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = {
  web: paperless(config.paperless) + {
    cronjob+: {
      spec+: {
        jobTemplate+: {
          spec+: {
            template+: {
              spec+: {
                initContainers: [
                  {
                    // init container to change permissions on the backup directory to 0777 due to bug in longhorn RWX support
                    command: ['sh', '-c', 'chmod 0777 /mnt/backups'],
                    image: 'busybox',
                    name: 'permissions',
                    volumeMounts: [{
                      mountPath: '/mnt/backups',
                      name: 'backups',
                    }],
                  },{
                    // init container to remove old backups
                    command: ['sh', '-c', 'find /mnt/backups -mtime +20 -type f -delete'],
                    image: 'busybox',
                    name: 'cleanup',
                    volumeMounts: [{
                      mountPath: '/mnt/backups',
                      name: 'backups',
                    }],
                  }
                ],
              },
            },
          },
        },
      },
    },
    database+:: {},
    databaseSecret: externalsecret(
      $.web.database.metadata,
      config.common.externalSecretStoreName,
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
      config.common.externalSecretStoreName,
      {
        PAPERLESS_ADMIN_USER: config.paperless.secretsRefs.user,
        PAPERLESS_ADMIN_PASSWORD: config.paperless.secretsRefs.pass,
        PAPERLESS_ADMIN_MAIL: config.paperless.secretsRefs.email,
        PAPERLESS_SECRET_KEY: config.paperless.secretsRefs.key,
      }
    ),

    pvcData+: {
      metadata+: {
        name: 'paperless-data',
      },
    },

    pvcMedia+: {
      metadata+: {
        name: 'paperless-media',
      },
    },

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
        } + config.paperless.ingress.labels,
      },
    },
  },
  postgres: postgres(config.postgres),
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
