local arr = import 'arr.libsonnet';
local prowlarr = import 'prowlarr.libsonnet';
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
  prowlarr: prowlarr(config.prowlarr) + {
    service+: lbService,
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
