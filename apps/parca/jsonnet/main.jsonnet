local agent = import 'github.com/parca-dev/parca-agent/deploy/lib/parca-agent/parca-agent.libsonnet';
// local ui = import 'github.com/parca-dev/parca/deploy/lib/parca/parca-ui.libsonnet';
local parca = import 'github.com/parca-dev/parca/deploy/lib/parca/parca.libsonnet';

local addArgs = (import '../../../lib/jsonnet/utils/container.libsonnet').addArgs;


local configYAML = (importstr '../settings.yaml');
local config = std.parseYaml(configYAML)[0];

local all = {
  agent: agent(config.agent) + {
    podSecurityPolicy+:: {},
    daemonSet+: {
      spec+: {
        template+: {
          metadata+: {
            annotations: {
              'parca.dev/scrape': 'true',
            },
          },
        },
      },
    },
  },
  parca: parca(config.parca) + {
    podSecurityPolicy+:: {},
    deployment+: {
      spec+: {
        template+: {
          metadata+: {
            annotations: {
              'checksum.config/md5': std.md5(std.toString(config.parca.config)),
              'parca.dev/scrape': 'true',
            },
          },
          spec+: {
            containers: std.map(
              function(c) if c.name == 'parca' then
                c {
                  readinessProbe: {
                    grpc: {
                      port: 7070,
                    },
                    initialDelaySeconds: 10,
                  },
                  livenessProbe: {
                    grpc: {
                      port: 7070,
                    },
                    initialDelaySeconds: 5,
                  },
                }
              else c,
              super.containers
            ),
          },
        },
      },
    },
    clusterRole: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: all.parca.serviceAccount.metadata { namespace:: '' },
      rules: [
        {
          apiGroups: [''],
          resources: ['pods'],
          verbs: ['list', 'watch'],
        },
        {
          apiGroups: [''],
          resources: ['nodes'],
          verbs: ['get'],
        },
      ],
    },
    clusterRoleBinding: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: all.parca.serviceAccount.metadata { namespace:: '' },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: all.parca.clusterRole.metadata.name,
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: all.parca.serviceAccount.metadata.name,
        namespace: all.parca.serviceAccount.metadata.namespace,
      }],
    },
    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: all.parca.serviceAccount.metadata {
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
          'traefik.ingress.kubernetes.io/router.middlewares': 'auth-traefik-forward-auth@kubernetescrd',
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
