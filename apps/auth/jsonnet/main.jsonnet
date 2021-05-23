local encryptedSecretsData = import './creds.json';
local oauth = import './oauth-proxy.libsonnet';

local configYAML = (importstr './settings.yaml');
local config = std.parseYaml(configYAML)[0] + {
  encryptedSecretsData: encryptedSecretsData,
};

local all = oauth(config);

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
