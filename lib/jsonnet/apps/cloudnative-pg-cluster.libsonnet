# Highly opinionated library to deploy postgres instance using cloudnative-pg and get secrets via external-secrets
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;

local defaults = {
  local defaults = self,
  name: 'postgres',
  namespace: error 'must provide namespace',
  image: '',
  resources: {
    requests: { cpu: '120m', memory: '200Mi' },
    //limits: { cpu: '400m', memory: '600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'postgres',
  },
  instances: 2,
  affinity: {
    enablePodAntiAffinity: true,
    topologyKey: 'kubernetes.io/hostname',
    podAntiAffinityType: 'required',
  },
  db: {
    name: 'postgres',
    user: '',
    backupRef: '',
    passRef: '',
    adminPassRef: '',
  },
  backup: {
    schedule: '0 17 23 */2 * *',
    retentionPolicy: '30d',
    destinationPath: '',
    endpointURL: '',
    accessKeyRef: '',
    secretKeyRef: '',
  },
  externalSecretStoreName: '',
  storage: {
    size: '100Mi',
    // storageClass: 'local-path',
  },
};

local externalSecretBasicAuth(metadata, secretStore, username, passRef) = externalsecret(
  metadata, secretStore, { password: passRef }
) + {
  spec+: {
    target+: {
      template+: {
        type: 'kubernetes.io/basic-auth',
        data: {
          username: username,
          password: '{{ .password }}',
        },
      },
    },
  },
};

function(params) {
  _config:: defaults + params + {
    db: defaults.db + params.db,
    backup: defaults.backup + params.backup,
    storage: defaults.storage + params.storage,
  },

  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  // Safety check
  assert std.isObject($._config.resources),

  credentialsUser: externalSecretBasicAuth(
    $._metadata + {name: $._config.name + '-user'} + {annotations+: { 'cnpg.io/reload': 'true' }},
    $._config.externalSecretStoreName,
    $._config.db.user,
    $._config.db.userPassRef
  ),

  credentialsAdmin: externalSecretBasicAuth(
    $._metadata + {name: $._config.name + '-admin'} + {annotations+: { 'cnpg.io/reload': 'true' }},
    $._config.externalSecretStoreName,
    'postgres',
    $._config.db.adminPassRef
  ),

  [if std.objectHas(params, 'backup') && std.objectHas(params.backup, 'secretKeyRef') && std.length(params.backup.secretKeyRef) > 0 then 'credentialsBackup']: externalsecret(
    $._metadata + {name: $._config.name + '-backup'} + {annotations+: { 'cnpg.io/reload': 'true' }},
    $._config.externalSecretStoreName,
    {
      S3_ACCESS_KEY: $._config.backup.accessKeyRef,
      S3_SECRET_KEY: $._config.backup.secretKeyRef,
    },
  ),

  [if std.objectHas(params, 'backup') && std.objectHas(params.backup, 'schedule') && std.length(params.backup.schedule) > 0 then 'backup']: {
    apiVersion: 'postgresql.cnpg.io/v1',
    kind: 'ScheduledBackup',
    metadata: $._metadata,
    spec: {
      backupOwnerReference: 'self',
      cluster: {
        name: $.cluster.metadata.name,
      },
      schedule: $._config.backup.schedule,
      suspend: false,
    },
  },

  cluster: {
    apiVersion: 'postgresql.cnpg.io/v1',
    kind: 'Cluster',
    metadata: $._metadata,
    spec: {
      [if std.objectHas(params, 'image') && std.length(params.image) > 0 then 'imageName']: $._config.image,
      instances: $._config.instances,
      monitoring: {
        enablePodMonitor: true,
      },
      superuserSecret: {
        name: $.credentialsAdmin.metadata.name,
      },
      backup:
        if !std.objectHas(params.db, 'backupRef') && std.objectHas(params, 'backup') && std.objectHas(params.backup, 'destinationPath') && std.length(params.backup.destinationPath) > 0 then
        {
          # target: 'primary',
          retentionPolicy: $._config.backup.retentionPolicy,
          barmanObjectStore: {
            destinationPath: $._config.backup.destinationPath,
            endpointURL: $._config.backup.endpointURL,
            s3Credentials: {
              accessKeyId: {
                name: $.credentialsBackup.metadata.name,
                key: 'S3_ACCESS_KEY',
              },
              secretAccessKey: {
                name: $.credentialsBackup.metadata.name,
                key: 'S3_SECRET_KEY',
              },
            },
            wal: {
              compression: 'gzip',
            },
          },
        }
        else
        {},
      bootstrap:
        local dbBootstrap = {
          database: $._config.db.name,
            owner: $._config.db.user,
            secret: {
              name: $.credentialsUser.metadata.name,
            },
        };
        if std.objectHas(params.db, 'backupRef') && std.length(params.db.backupRef) > 0 then {
          recovery: {
            backup: {
              name: $._config.db.backupRef,
            },
          } + dbBootstrap,
        } else {
          initdb: dbBootstrap,
        },
      affinity: $._config.affinity,
      resources: $._config.resources,
      storage: $._config.storage,
    },
  },
}
