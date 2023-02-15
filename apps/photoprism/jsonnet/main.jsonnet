local photoprism = import 'photoprism.libsonnet';
local externalsecret = (import '../../../lib/jsonnet/utils/externalsecrets.libsonnet').externalsecret;

local config = std.parseYaml(importstr '../settings.yaml')[0];

local all = photoprism(config.photoprism) + {
  credentials: externalsecret(
    {
      name: 'credentials',
      namespace: config.photoprism.namespace,
    },
    'doppler-auth-api',
    config.photoprism.credentialsRefs,
  ),
  ingress+: {
    metadata+: {
      labels+: {
        probe: 'enabled',
      },
      annotations+: {
        // Default is very low so most photo uploads will fail
        'nginx.ingress.kubernetes.io/proxy-body-size': '512M',
      },
    },
  },
  statefulSet+: {
    spec+: {
      template+: {
        spec+: {
          nodeSelector: {
            'kubernetes.io/arch': 'amd64',
          },
        },
      },
    },
  },
  pv: {
    apiVersion: 'v1',
    kind: 'PersistentVolume',
    metadata: {
      name: 'originals',
      namespace: 'photoprism',
    },
    spec: {
      accessModes: ['ReadWriteOnce'],
      capacity: {
        storage: '4000Gi',
      },
      nfs: {
        path: '/Multimedia/Final Cut',
        server: '192.168.2.29',
      },
      persistentVolumeReclaimPolicy: 'Retain',
      storageClassName: 'manual',
      volumeMode: 'Filesystem',
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
