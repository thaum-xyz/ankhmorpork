local t = import 'kube-thanos/thanos.libsonnet';
local externalsecret = (import '../../../lib/jsonnet/utils/externalsecrets.libsonnet').externalsecret;
local settings = std.parseYaml(importstr '../settings.yaml')[0];

local i = t.receiveIngestor(settings + settings.receiveIngestor + {
  replicaLabels: ['replica', 'receive_replica'],
  replicationFactor: 1,
  serviceMonitor: true,
});

local r = t.receiveRouter(settings + settings.receiveRouter + {
  replicaLabels: ['replica', 'receive_replica'],
  replicationFactor: 1,
  endpoints: i.endpoints,
});

local s = t.store(settings + settings.store + {
  serviceMonitor: true,
});

local q = t.query(settings + settings.query + {
  replicaLabels: ['replica', 'prometheus_replica', 'rule_replica'],
  serviceMonitor: true,
  stores: [s.storeEndpoint] + i.storeEndpoints,
});

local c = t.compact(settings + settings.compact + {
  serviceMonitor: true,
});

local all = {
  query: q,
  store: s {
    statefulSet+: {
      spec+: {
        template+: {
          spec+: {
            /*affinity: {
              podAntiAffinity: {
                requiredDuringSchedulingIgnoredDuringExecution: [{
                  labelSelector: {
                    matchExpressions: [{
                      key: 'app.kubernetes.io/name',
                      operator: 'In',
                      values: ['thanos-receive'],
                    }],
                  },
                  topologyKey: 'kubernetes.io/hostname',
                }],
              },
            },*/
            nodeSelector+: {
              'kubernetes.io/arch': 'amd64',
            },
          },
        },
      },
    },
  },
  receiveIngestor: {
    [resource]: i[resource]
    for resource in std.objectFields(i)
    if resource != 'ingestors'
  } + {
    ['ingestor-' + hashring + '-' + resource]: i.ingestors[hashring][resource]
    for hashring in std.objectFields(i.ingestors)
    for resource in std.objectFields(i.ingestors[hashring])
    if i.ingestors[hashring][resource] != null
  } + {
    'ingestor-default-statefulSet'+: {
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
  },
  receiveRouter: r {
    serviceMonitor: $.receiveIngestor.serviceMonitor {
      metadata: r.service.metadata,
      spec+: {
        selector+: {
          matchLabels: {
            'app.kubernetes.io/component': r.service.metadata.labels['app.kubernetes.io/component'],
            'app.kubernetes.io/name': r.service.metadata.labels['app.kubernetes.io/name'],
          },
        },
      },
    },
  },
  compact: c,
  custom: {
    bucketConfig: externalsecret(
      {
        name: settings.objectStorageConfig.name,
        namespace: settings.namespace,
      },
      'doppler-auth-api',
      settings.objectStorageConfig.credentialsRefs,
    ) + {
      spec+: {
        target+: {
          template+: {
            engineVersion: 'v2',
            data: {
              [settings.objectStorageConfig.key]: settings.objectStorageConfig.content,
            },
          },
        },
      },
    },
    thanosReceiveIngressAuth: externalsecret(
      {
        name: 'thanos-receive-ingress-auth',
        namespace: settings.namespace,
      },
      'doppler-auth-api',
      {
        auth: settings.ingressAuthHTPasswdRef,
      }
    ),
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

local mixin = (import 'github.com/thanos-io/thanos/mixin/mixin.libsonnet') + {
  _config+:: {
  },
  compact:: null,
  sidecar:: null,
  rule:: null,
  bucketReplicate:: null,
};

local monitoring = {
  _metadata:: {
    labels: {
      prometheus: 'k8s',
      role: 'alert-rules',
    },
    namespace: settings.namespace,
  },
  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata {
      name: 'thanos-rules',
    },
    spec: {
      local r = if std.objectHasAll(mixin, 'prometheusRules') then mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll(mixin, 'prometheusAlerts') then mixin.prometheusAlerts.groups else [],
      groups: a + r,
    },
  },

  thanosReceiveRequestsErrors: {
    apiVersion: 'pyrra.dev/v1alpha1',
    kind: 'ServiceLevelObjective',
    metadata: $._metadata {
      name: 'thanos-receive-requests-errors',
    },
    spec: {
      description: '',
      indicator: {
        ratio: {
          errors: {
            metric: 'http_requests_total{code=~"5..", job=~".*thanos-receive.*", handler="receive"}',
          },
          total: {
            metric: 'http_requests_total{job=~".*thanos-receive.*", handler="receive"}',
          },
        },
      },
      target: '99',
      window: '2w',
    },
  },
  thanosReceiveRequestsLatency: {
    apiVersion: 'pyrra.dev/v1alpha1',
    kind: 'ServiceLevelObjective',
    metadata: $._metadata {
      name: 'thanos-receive-requests-latency',
    },
    spec: {
      description: '',
      indicator: {
        latency: {
          success: {
            metric: 'http_request_duration_seconds_bucket{job=~".*thanos-receive.*", handler="receive", le="5.0"}',
          },
          total: {
            metric: 'http_request_duration_seconds_count{job=~".*thanos-receive.*", handler="receive"}',
          },
        },
      },
      target: '99',
      window: '2w',
    },
  },
};

// Manifestation
{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
} + {
  ['monitoring/' + resource + '.yaml']: std.manifestYamlDoc(monitoring[resource])
  for resource in std.objectFields(monitoring)
}
