local arr = import 'arr.libsonnet';
local plex = import 'plex.libsonnet';

local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;
local utils = import 'utils.libsonnet';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local lbService = {
  metadata+: {
    annotations+: {
      'metallb.universe.tf/address-pool': 'default',
      'metallb.universe.tf/allow-shared-ip': 'multimedia-svc',
    },
  },
  spec+: {
    externalTrafficPolicy: 'Cluster',
    loadBalancerIP: config.common.loadBalancerIP,
    sessionAffinity: 'None',
    type: 'LoadBalancer',
    clusterIP:: null,
  },
};

local all = {
  sonarr: arr(config.sonarr) + {
    service+: lbService,
  },
  radarr: arr(config.radarr) + {
    service+: lbService,
  },
  prowlarr: arr(config.prowlarr) + {
    service+: lbService,
  },

  plex: plex(config.plex) + {
    plexClaim: externalsecret(
      {
        name: config.plex.plexClaim.secretName,
        namespace: config.plex.namespace,
      },
      config.plex.externalSecretStoreName,
      { PLEX_CLAIM: config.plex.plexClaim.remoteRef }
    ),
    plexToken: externalsecret(
      {
        name: config.plex.exporter.config.secretName,
        namespace: config.plex.namespace,
      },
      config.plex.externalSecretStoreName,
      { token: config.plex.exporter.config.remoteRef }
    ) + {
      spec+: {
        target: {
          name: config.plex.exporter.config.secretName,
          template: {
            engineVersion: 'v2',
            data: {
              'config.json': |||
                {
                  "exporter": {
                    "port": 9594
                  },
                  "server": {
                    "address": "127.0.0.1",
                    "port": 32400,
                    "token": "{{ .token }}"
                  }
                }
              |||,
            },
          },
        },
      },
    },
  },

  shared:
    utils.persistentVolume({ name: 'downloaded', namespace: config.common.namespace }, '100Gi', 'qnap-nfs') +
    utils.persistentVolume({ name: 'tv', namespace: config.common.namespace }, '4000Gi', 'manual', '192.168.2.29') +
    utils.persistentVolume({ name: 'movies', namespace: config.common.namespace }, '4000Gi', 'manual', '192.168.2.29') +
    {
      'pv-downloaded':: {},
      'pvc-downloaded'+: {
        spec+: {
          accessModes: ['ReadWriteMany'],
          volumeName:: {},
        },
      },
    },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
