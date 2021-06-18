local encryptedSecretsData = import './creds.json';
local oauth = import 'github.com/thaum-xyz/jsonnet-libs/apps/oauth2-proxy/oauth2-proxy.libsonnet';

local configYAML = (importstr '../settings.yaml');
local config = std.parseYaml(configYAML)[0] {
  encryptedSecretsData: encryptedSecretsData,
};

local all = oauth(config);

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
