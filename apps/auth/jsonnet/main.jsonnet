local encryptedSecretsData = import './creds.json';
local oauth = import './oauth-proxy.libsonnet';

local config = {
  version: '7.1.2',
  image: 'quay.io/paulfantom/oauth2-proxy:' + self.version,
  namespace: 'auth',
  replicas: 2,
  ingressDomain: 'auth.ankhmorpork.thaum.xyz',
  encryptedSecretsData: encryptedSecretsData,
  resources: {
    requests: { cpu: '10m', memory: '13Mi' },
    limits: { cpu: '30m', memory: '30Mi' },
  },
};

local all = oauth(config);
/* + {
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
