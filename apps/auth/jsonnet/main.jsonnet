local oauth = import './oauth-proxy.libsonnet';
local encryptedSecretsData = import './creds.json';

local config = {
  version: '6.1.1',
  image: 'quay.io/paulfantom/oauth2-proxy:' + self.version,
  namespace: 'auth',
  replicas: 2,
  ingressDomain: 'auth.ankhmorpork.thaum.xyz',
  encryptedSecretsData: encryptedSecretsData,
};

local all = oauth(config);/* + {
  ingress+: {
    metadata+: {
      labels+: {
        probe: 'enabled',
      },
    },
  },
};
*/

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }