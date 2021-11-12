local ghost = import 'github.com/thaum-xyz/jsonnet-libs/apps/ghost/ghost.libsonnet';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = ghost(config) + {
  pvc+: {
    metadata+: {
      name: 'data',
    },
    spec+: {
      storageClassName: 'managed-nfs-storage',
    },
  },
  ingress+: {
    metadata+: {
      labels+: {
        probe: 'enabled',
      },
    },
  },
  psp: {
    apiVersion: 'policy/v1beta1',
    kind: 'PodSecurityPolicy',
    metadata: $.deployment.metadata,
    spec: {
      fsGroup: {
        rule: "RunAsAny",
      },
      hostPorts: [{
        max: 0,
        min: 0,
      }],
      runAsUser: {
        rule: 'RunAsAny',
      },
      seLinux: {
        rule: "RunAsAny",
      },
      supplementalGroups: {
        rule: 'RunAsAny',
      },
      volumes: [
        'persistentVolumeClaim',
        'emptyDir',
      ],
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
