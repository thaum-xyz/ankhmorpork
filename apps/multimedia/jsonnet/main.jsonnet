local arr = import 'arr.libsonnet';
local ombi = import 'ombi.libsonnet';
local prowlarr = import 'prowlarr.libsonnet';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

/*
local config = {
  jackett: {
    version: "1",
    image: "asd",
    namespace: "multimedia",
  },
};
*/

local nodeSelector = {
  "kubernetes.io/arch": "amd64",
  "storage.infra/main": "true",
};

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
    statefulset+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: nodeSelector,
          },
        },
      },
    },
  },
  radarr: arr(config.radarr) + {
    service+: lbService,
    statefulset+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: nodeSelector,
          },
        },
      },
    },
  },
  prowlarr: prowlarr(config.prowlarr) + {
    service+: lbService,
  },
  ombi: ombi(config.ombi),
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
