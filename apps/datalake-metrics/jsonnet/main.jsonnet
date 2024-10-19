local t = import 'kube-thanos/thanos.libsonnet';
local externalsecret = (import '../../../lib/jsonnet/utils/externalsecrets.libsonnet').externalsecret;
local settings = std.parseYaml(importstr '../settings.yaml')[0];

local i = t.receiveIngestor(std.mergePatch(settings, settings.receiveIngestor));

local s = t.store(std.mergePatch(settings, settings.store));

local q = t.query(settings + settings.query + {
  stores: [s.storeEndpoint] + i.storeEndpoints,
});

local c = t.compact(std.mergePatch(settings, settings.compact));

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
  compact: c,
  custom: {
    hashring: {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'hashring-config',
        namespace: settings.namespace,
      },
      data: {
        'hashrings.json': '[{"endpoints": ["thanos-receive-ingestor-default-0.thanos-receive-ingestor-default.datalake-metrics.svc.cluster.local:10901", "thanos-receive-ingestor-default-1.thanos-receive-ingestor-default.datalake-metrics.svc.cluster.local:10901", "thanos-receive-ingestor-default-2.thanos-receive-ingestor-default.datalake-metrics.svc.cluster.local:10901"], "hashring": "default", "tenants": [ ]}]',
      },
    },
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
        users: settings.ingressAuthHTPasswdRef,
      }
    ),
    middlewareAuth: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'Middleware',
      metadata: {
        name: 'basicauth',
        namespace: settings.namespace,
      },
      spec: {
        basicAuth: {
          removeHeader: true,
          secret: $.custom.thanosReceiveIngressAuth.metadata.name,
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
          'traefik.ingress.kubernetes.io/router.middlewares': $.custom.middlewareAuth.metadata.namespace + '-' + $.custom.middlewareAuth.metadata.name + '@kubernetescrd',
        },
      },
      spec: {
        ingressClassName: 'public',
        rules: [{
          host: 'metrics.datalake.ankhmorpork.thaum.xyz',
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: 'thanos-receive-ingestor-default',
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
      alerting: {
        name: 'ThanosErrorBudgetBurn',
      },
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
      alerting: {
        name: 'ThanosErrorBudgetBurn',
      },
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
