local t = import 'kube-thanos/thanos.libsonnet';
local settings = std.parseYaml(importstr '../settings.yaml')[0];

local i = t.receiveIngestor(settings {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
  // objectStorageConfig: null,
  serviceMonitor: true,
});

local r = t.receiveRouter(settings {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
  // objectStorageConfig: null,
  endpoints: i.endpoints,
});

local s = t.store(settings {
  replicas: 1,
  serviceMonitor: true,
});

local q = t.query(settings {
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
    [settings.objectStorageConfig.name]: {
      apiVersion: 'v1',
      kind: 'Secret',
      metadata: {
        name: settings.objectStorageConfig.name,
        namespace: settings.namespace,
      },
      data: {
        [settings.objectStorageConfig.key]: std.base64(std.toString(settings.objectStorageConfig.content)),
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
          auth: 'AgDJqfrb+mSzHQ9DsiuO6iF+TYeS4EdHtM2l2ds9XlX+by5P3pmHHwY/gMSCfgyDUfLOV8+gaBmwGAkybDUJ9Aijc3O/YvCIR4clnm0DvvefZ2L2TlrApPGZdOjm8Rvgsa1D10ZLrav5yv/krBEgf10cShh6HvABidEZt+mbbVsSQ35cyM4mK60GWIDJyNIqxVn3dl2TxAQFQSpNxPlj5lo7K6qg7vobbp9oV7yX6JTAmqgN2kUNiFcvJtSulchFHnss1ZKtG5PSm1Sl7T8gdoQrfKlMu+jp2o86HXl1UtAf1Zx/BKAWpWl/lHTtuM2bK2r1ET7StEhuenLZUPgE6D8wqVqk95WqIcKP/usuVP7ztPEr/rns6Nm5WfXWc6EDAtPRzkYWcAxnR04uRB+PzRYKDeb/EpqfPuNK8O65/OFwzBeMykmIHZNvWKL18tH1OQeDr1+zgiwzkcV/4olm2g1Q2Y2zKQA5K2c7wf3uA+WqgXofB26ZOYkHuJ3Vpgy5udTxpLToUlCYSxn1dVd7ouitZkIjrLWFPDZORw0eIX/JiyabtYeLnEQOZDJQVkdHNoWyU/IuI6nRyo8q0ltzrdezpHUNld2HwBZd9PbuJ2dz0Asm77apeqRRTUoFOXMThhO/RVS/l5kO1SiI+2Ef1WANYMP0sBckhzdOJ7VuoEkbPsBarvZJvPivWCew7f+og5mIHfoxda2t/xhdBIbZgXRTHjOTUT57yzxP237/v4QV1rx47vc3L87MKNsJei1K',
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
          'nginx.ingress.kubernetes.io/auth-secret': 'thanos-receive-ingress-auth',
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
