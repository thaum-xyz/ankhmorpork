local encryptedSecretsData = import './creds.json';
local oauth = import 'github.com/thaum-xyz/jsonnet-libs/apps/oauth2-proxy/oauth2-proxy.libsonnet';

local addArgs(args, name, containers) = std.map(
  function(c) if c.name == name then
    c {
      args+: args,
    }
  else c,
  containers,
);

local configYAML = (importstr '../settings.yaml');
local config = std.parseYaml(configYAML)[0] {
  encryptedSecretsData: encryptedSecretsData,
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
          containers: addArgs(['--skip-auth-regex=^/-/healthy', '--skip-auth-regex=^/api/health'], 'oauth2-proxy', super.containers),
          nodeSelector+: {
            'network.infra/type': 'fast',
          },
        },
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
