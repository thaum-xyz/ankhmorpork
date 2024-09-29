local postgres = import 'apps/cloudnative-pg-cluster.libsonnet';
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

local pgWALLimit = {
  spec+: {
    postgresql+: {
      parameters+: {
        max_slot_wal_keep_size: '3GB',
      },
    },
  },
};

local logsDBInit(user) = {
  spec+: {
    bootstrap+: {
      initdb+: {
        postInitSQL: [
          'CREATE DATABASE logs;',
          'ALTER DATABASE logs OWNER TO %s;' % user,
        ],
      },
    },
  },
};

local all = {
  sonarr: arr(config.sonarr) + {
    service+: lbService,
    ingress+: {
      metadata+: {
        annotations+: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-dns01',
          'reloader.homer/group': 'Multimedia',
          'reloader.homer/logo': 'https://avatars3.githubusercontent.com/u/1082903?s=200&v=4',
          'reloader.homer/name': 'Sonarr',
          'reloader.homer/subtitle': 'TV shows collection management',
          'reloader.homer/tag': 'local',
        },
        labels: {
          'reloader.homer/enabled': 'true',
          //probe: 'enabled',
        },
      },
    },
  },
  sonarrdb: postgres(config.sonarr.postgres) + {
    cluster+: logsDBInit(config.sonarr.postgres.db.user),
  },

  radarr: arr(config.radarr) + {
    service+: lbService,
    ingress+: {
      metadata+: {
        annotations+: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-dns01',
          'reloader.homer/group': 'Multimedia',
          'reloader.homer/logo': 'https://avatars1.githubusercontent.com/u/25025331?s=200&v=4',
          'reloader.homer/name': 'Radarr',
          'reloader.homer/subtitle': 'Movie collection management',
          'reloader.homer/tag': 'local',
        },
        labels: {
          'reloader.homer/enabled': 'true',
          //probe: 'enabled',
        },
      },
    },
  },
  radarrdb: postgres(config.radarr.postgres) + {
    cluster+: logsDBInit(config.radarr.postgres.db.user) + pgWALLimit,
  },

  prowlarr: arr(config.prowlarr) + {
    service+: lbService,
    ingress+: {
      metadata+: {
        annotations+: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-dns01',
          'reloader.homer/group': 'Multimedia',
          'reloader.homer/logo': 'https://avatars.githubusercontent.com/u/73049443?s=200&v=4',
          'reloader.homer/name': 'Prowlarr',
          'reloader.homer/subtitle': 'Indexer/proxy management',
          'reloader.homer/tag': 'local',
        },
        labels: {
          'reloader.homer/enabled': 'true',
          //probe: 'enabled',
        },
      },
    },
  },
  prowlarrdb: postgres(config.prowlarr.postgres) + {
    cluster+: logsDBInit(config.prowlarr.postgres.db.user),
  },

  /*bazarr: arr(config.bazarr) + {
    service+: lbService,
  },
  bazarrdb: postgres(config.bazarr.postgres) + {
    cluster+: logsDBInit(config.bazarr.postgres.db.user),
  },*/

  readarr: arr(config.readarr) + {
    prometheusRule+:: {},
    service+: lbService {
      metadata+: {
        annotations: {
          'metallb.universe.tf/address-pool': 'default',
        },
      },
      spec+: {
        loadBalancerIP:: null,
      },
    },
    ingress+: {
      metadata+: {
        annotations+: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-dns01',
          'reloader.homer/group': 'Multimedia',
          'reloader.homer/logo': 'https://avatars.githubusercontent.com/u/57576474?s=200&v=4',
          'reloader.homer/name': 'Readarr',
          'reloader.homer/subtitle': 'Books collection management',
          'reloader.homer/tag': 'local',
        },
        labels: {
          'reloader.homer/enabled': 'true',
          //probe: 'enabled',
        },
      },
    },
  },
  readarrdb: postgres(config.readarr.postgres) + {
    cluster+: {
      spec+: {
        bootstrap+: {
          initdb+: {
            postInitSQL: [
              'CREATE DATABASE logs;',
              'ALTER DATABASE logs OWNER TO %s;' % config.readarr.postgres.db.user,
              'CREATE DATABASE readarr-cache;',
              'ALTER DATABASE readarr-cache OWNER TO %s;' % config.readarr.postgres.db.user,
            ],
          },
        },
      },
    },
  },

  plex: plex(config.plex) + {
    statefulset+: {
      spec+: {
        replicas: 0,
      },
    },
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
