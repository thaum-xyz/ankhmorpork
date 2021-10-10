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



local configYAML = (importstr '../settings.yaml');
local config = std.parseYaml(configYAML)[0];

local all = {
  agent: agent(config.agent) + {
    // TODO: remove after https://github.com/parca-dev/parca-agent/pull/88 is merged
    metadata:: all.agent.serviceAccount.metadata,
    clusterRoleBinding+: {
      metadata: all.agent.metadata,
    },
    clusterRole+: {
      metadata: all.agent.metadata,
    },
    roleBinding+: {
      metadata: all.agent.metadata,
    },
    role+: {
      metadata: all.agent.metadata,
    },
    podSecurityPolicy+: {
      metadata: all.agent.metadata,
    },
    daemonSet+: {
      metadata: all.agent.metadata,
      // TODO: remove after https://github.com/parca-dev/parca-agent/issues/90 is solved
      spec+: {
        template+: {
          spec+: {
            containers: addArgs(['--socket-path=/run/k3s/containerd/containerd.sock'], 'parca-agent', super.containers),
          },
        },
      },
    },
    // TODO: remove after https://github.com/parca-dev/parca-agent/pull/89 is merged
    podMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PodMonitor',
      metadata: {
        name: all.agent.config.name,
        namespace: all.agent.config.namespace,
        labels: all.agent.config.commonLabels,
      },
      spec: {
        podMetricsEndpoints: [{
          port: all.agent.daemonSet.spec.template.spec.containers[0].ports[0].name,
        }],
        selector: {
          matchLabels: all.agent.daemonSet.spec.template.metadata.labels,
        },
      },
    },
  },
  parca: parca(config.parca) + {
  // TODO: remove after https://github.com/parca-dev/parca/pull/274 is merged
    deployment+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector+: {
              'kubernetes.io/arch': 'amd64',
            },
          },
        },
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
