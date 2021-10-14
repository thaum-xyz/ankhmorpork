local agent = import 'github.com/parca-dev/parca-agent/deploy/lib/parca-agent/parca-agent.libsonnet';
// local ui = import 'github.com/parca-dev/parca/deploy/lib/parca/parca-ui.libsonnet';
local parca = import 'github.com/parca-dev/parca/deploy/lib/parca/parca.libsonnet';

// TODO: move this to thaum-xyz/jsonnet-libs
local addArgs(args, name, containers) = std.map(
  function(c) if c.name == name then
    c {
      args+: args,
    }
  else c,
  containers,
);


local parcaConfig = (importstr '../parca.yaml');
local configYAML = (importstr '../settings.yaml');
local config = std.parseYaml(configYAML)[0];

local all = {
  agent: agent(config.agent) + {
    daemonSet+: {
      // TODO: remove after https://github.com/parca-dev/parca-agent/issues/90 is solved
      spec+: {
        template+: {
          spec+: {
            containers: addArgs(['--socket-path=/run/k3s/containerd/containerd.sock'], 'parca-agent', super.containers),
          },
        },
      },
    },
  },
  parca: parca(config.parca) + {
    configmap+: {
      data: {
        'parca.yaml': parcaConfig,
      }
    },
    // FIXME: THAT'S AN UPSTREAM BUG
    service+: {
      spec+: {
        ports: [{
          name: 'http',
          port: 7070,
          targetPort: 7070,
        }],
      },
    },
    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: all.parca.serviceAccount.metadata {
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
          'kubernetes.io/ingress.class': 'nginx',
          'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.ankhmorpork.thaum.xyz/oauth2/start?rd=$scheme://$host$escaped_request_uri',
          'nginx.ingress.kubernetes.io/auth-url': 'https://auth.ankhmorpork.thaum.xyz/oauth2/auth',
        },
      },
      spec: {
        tls: [{
          secretName: 'parca-ingress-tls',
          hosts: [config.domain],
        }],
        rules: [{
          host: config.domain,
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: all.parca.service.metadata.name,
                  port: {
                    name: all.parca.service.spec.ports[0].name,
                  },
                },
              },
            }],
          },
        }],
      },
    },

  },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
