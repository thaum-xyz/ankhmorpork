local kured = import './kured.libsonnet';

local configYAML = (importstr './settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = {
  kured: kured(config.kured) {
    daemonSet+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: {
              'kubernetes.io/arch': 'arm64',  // TODO: Move NFS storage to QNAP and allow amd64 hosts to reboot
            },
          },
        },
      },

    },
  },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
