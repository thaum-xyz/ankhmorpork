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
  db: {
    name: 'postgres',
    user: '',
    passRef: '',
    adminPassRef: '',
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
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  // Safety check
  assert std.isObject($._config.resources),

  credentialsUser: externalSecretBasicAuth(
    $._metadata + {name: $._config.name + '-user'},
    $._config.externalSecretStoreName,
    $._config.db.user,
    $._config.db.userPassRef
  ),
  credentialsAdmin: externalSecretBasicAuth(
    $._metadata + {name: $._config.name + '-admin'},
    $._config.externalSecretStoreName,
    'postgres',
    $._config.db.adminPassRef
  ),
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
      bootstrap: {
        initdb: {
          database: $._config.db.name,
          owner: $._config.db.user,
          secret: {
            name: $.credentialsUser.metadata.name,
          },
        },
      },
      resources: $._config.resources,
      storage: $._config.storage,
    },
  },
}