local miniflux = import './miniflux.libsonnet';
local postgres = import './postgres.libsonnet';
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0];

local all = {
  postgres: postgres(config.postgres) {
    secret: sealedsecret(
      $.postgres.serviceAccount.metadata,
      config.postgres.encryptedEnvs
    ) {
      spec+: {
        template+: {
          data: {
            POSTGRES_DB: 'miniflux',
          },
        },
      },
    },
  },
  miniflux: miniflux(config.miniflux) {
    postgresCreds:: $.postgres.secret,
    config: sealedsecret(
      $.miniflux.serviceAccount.metadata,
      {
        ADMIN_USERNAME: config.miniflux.admin.user,
        ADMIN_PASSWORD: config.miniflux.admin.pass,
      }
    ) {
      spec+: {
        template+: {
          data: {
            // https://miniflux.app/docs/configuration.html
            // TODO: Move this into `miniflux.libsonnet`
            RUN_MIGRATIONS: '1',
            CREATE_ADMIN: '1',
            POSTGRES_SVC: $.postgres.service.metadata.name + '.' + $.postgres.service.metadata.namespace + '.svc',
            BASE_URL: 'https://' + config.miniflux.domain,
            METRICS_COLLECTOR: '1',
            METRICS_ALLOWED_NETWORKS: '10.42.0.1/16',
          },
        },
      },
    },
    serviceMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: $.miniflux.service.metadata,
      spec: {
        endpoints: [{
          port: $.miniflux.service.spec.ports[0].name,
          interval: '60s',
        }],
        selector: {
          matchLabels: $.miniflux.service.spec.selector,  // It works because all selectors are unified
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
