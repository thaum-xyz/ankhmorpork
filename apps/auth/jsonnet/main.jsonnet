local oauth = import 'oauth2-proxy.libsonnet';
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;
local addArgs = (import 'utils/container.libsonnet').addArgs;

local settings = std.parseYaml(importstr '../settings.yaml')[0];

local creds = externalsecret(
  {
    name: 'oauth-creds',
    namespace: settings.namespace,
  },
  'doppler-auth-api',
  settings.credentialsRefs,
);

local config = settings {
  encryptedSecretsData: creds,
};

local all = oauth(config) + {
  deployment+: {
    spec+: {
      template+: {
        metadata+: {
          annotations: {
            'checksum.config/md5': std.md5(std.toString(config)),
          },
        },
        spec+: {
          nodeSelector+: {
            'network.infra/type': 'fast',
          },
        },
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
