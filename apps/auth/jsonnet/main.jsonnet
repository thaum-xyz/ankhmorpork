local encryptedSecretsData = import './creds.json';
local oauth = import 'github.com/thaum-xyz/jsonnet-libs/apps/oauth2-proxy/oauth2-proxy.libsonnet';

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
          labels+: {
            "parca.dev/scrape": "true",
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
