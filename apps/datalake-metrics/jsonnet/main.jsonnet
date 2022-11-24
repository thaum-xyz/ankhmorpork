local t = import 'kube-thanos/thanos.libsonnet';
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;
local settings = std.parseYaml(importstr '../settings.yaml')[0];

local i = t.receiveIngestor(settings + settings.receiveIngestor + {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
  serviceMonitor: true,
});

local r = t.receiveRouter(settings + settings.receiveRouter + {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
  endpoints: i.endpoints,
});

local s = t.store(settings + settings.store + {
  replicas: 1,
  serviceMonitor: true,
});

local q = t.query(settings + settings.query + {
  replicas: 1,
  replicaLabels: ['prometheus_replica', 'rule_replica'],
  serviceMonitor: true,
  stores: [s.storeEndpoint] + i.storeEndpoints,
});

local all = {
  query: q,
  store: s,
  receiveRouter: r,
  receiveIngestor: {
    [resource]: i[resource]
    for resource in std.objectFields(i)
    if resource != 'ingestors'
  } + {
    ['ingestor-' + hashring + '-' + resource]: i.ingestors[hashring][resource]
    for hashring in std.objectFields(i.ingestors)
    for resource in std.objectFields(i.ingestors[hashring])
    if i.ingestors[hashring][resource] != null
  },
  custom: {
    bucketConfig: sealedsecret(
      {
        name: settings.objectStorageConfig.name,
        namespace: settings.namespace,
      }, {
        ACCESS_KEY: settings.objectStorageConfig.encryptedData.ACCESS_KEY,
        SECRET_KEY: settings.objectStorageConfig.encryptedData.SECRET_KEY,
      }
    ) + {
      spec+: {
        template+: {
          data: {
            [settings.objectStorageConfig.key]: settings.objectStorageConfig.content,
          },
        },
      },
    },
    thanosReceiveIngressAuth: {
      kind: 'SealedSecret',
      apiVersion: 'bitnami.com/v1alpha1',
      metadata: {
        name: 'thanos-receive-ingress-auth',
        namespace: 'datalake-metrics',
      },
      spec: {
        template: {
          metadata: {
            name: 'thanos-receive-ingress-auth',
            namespace: 'datalake-metrics',
          },
        },
        encryptedData: {
          auth: settings.ingressAuth,
        },
      },
    },
    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: 'thanos-receive',
        namespace: settings.namespace,
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
          'nginx.ingress.kubernetes.io/auth-type': 'basic',
          'nginx.ingress.kubernetes.io/auth-secret': $.custom.thanosReceiveIngressAuth.metadata.name,
          'nginx.ingress.kubernetes.io/auth-realm': 'Authentication Required',
        },
      },
      spec: {
        ingressClassName: 'nginx',
        rules: [{
          host: 'metrics.datalake.ankhmorpork.thaum.xyz',
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: 'thanos-receive-router',
                  port: {
                    name: 'remote-write',
                  },
                },
              },
            }],
          },
        }],
        tls: [{
          hosts: ['metrics.datalake.ankhmorpork.thaum.xyz'],
          secretName: 'thanos-receive-ingress-tls',
        }],
      },
    },
  },
};

// Manifestation
{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
