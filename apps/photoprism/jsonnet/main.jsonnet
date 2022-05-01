local photoprism = import 'photoprism.libsonnet';
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local config = std.parseYaml(importstr '../settings.yaml')[0];

local all = {
  photoprism: photoprism(config.photoprism) + {
    credentials: sealedsecret(
      {
        name: 'credentials',
        namespace: config.photoprism.namespace,
      },
      {
        PHOTOPRISM_ADMIN_PASSWORD: config.photoprism.credentials.admin,
        PHOTOPRISM_DATABASE_PASSWORD: config.photoprism.credentials.database,
      }
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
  },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
