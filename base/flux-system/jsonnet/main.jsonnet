local extrenalsecret = (import '../../../lib/jsonnet/utils/externalsecrets.libsonnet').externalsecret;

local all = {
  _metadata:: {
    name: 'flux',
    namespace: 'flux-system',
    labels: {
      'app.kubernetes.io/instance': 'flux-system',
      'app.kubernetes.io/part-of': 'flux',
    },
  },

  certManagerPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: $._metadata {
      name: 'allow-cert-manager',
    },
    spec: {
      ingress: [{
        from: [{
          namespaceSelector: {},
        }],
      }],
      podSelector: {
        matchLabels: {
          'acme.cert-manager.io/http01-solver': 'true',
        },
      },
      policyTypes: ['Ingress'],
    },
  },

  ingress: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: {
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
      },
    },
    spec: {
      ingressClassName: 'traefik',
      rules: [{
        host: 'flux.ankhmorpork.thaum.xyz',
        http: {
          paths: [{
            backend: {
              service: {
                name: 'notification-controller',
                port: { name: 'http' },
              },
            },
            path: '/',
            pathType: 'Prefix',
          }],
        },
      }],
      tls: [{
        hosts: ['flux.ankhmorpork.thaum.xyz'],
        secretName: 'flux-tls',
      }],
    },
  },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata {
      labels+: {
        prometheus: 'k8s',
        role: 'alert-rules',
      },
    },
    spec: {
      groups: [{
        name: 'GitOpsToolkit',
        rules: [{
          alert: 'ReconciliationFailure',
          expr: |||
            sum by (kind, name, namespace) (
              max_over_time(gotk_reconcile_condition{status=~"False|Unknown",type="Ready"}[3m])
            ) != 0
          |||,
          'for': '20m',
          labels: {
            severity: 'warning',
          },
          annotations: {
            summary: 'Flux objects reconciliation failure',
            description: '{{ $labels.kind }} {{ $labels.namespace }}/{{ $labels.name }} reconciliation has been failing for more than 10 minutes.',
          },
        }],
      }],
    },
  },

  // Based on https://github.com/fluxcd/flux2/blob/main/manifests/monitoring/monitoring-config/podmonitor.yaml
  podMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PodMonitor',
    metadata: $._metadata {
      name: 'flux-system',
    },
    spec: {
      namespaceSelector: {
        matchNames: ['flux-system'],
      },
      selector: {
        matchExpressions: [{
          key: 'app',
          operator: 'In',
          values: [
            'helm-controller',
            'source-controller',
            'kustomize-controller',
            'notification-controller',
            'image-automation-controller',
            'image-reflector-controller',
          ],
        }],
      },
      podMetricsEndpoints: [{
        port: 'http-prom',
        // Custom
        honorLabels: true,  // Allow overriding `namespace` label
        metricRelabelings: [{
          action: 'drop',
          regex: 'rest_client_request_latency_seconds.*',
          sourceLabels: ['__name__'],
        }],
      }],
    },

  },
  githubToken: extrenalsecret(
    {
      name: 'github-webhook-token',
      namespace: $._metadata.namespace,
    },
    'doppler-auth-api',
    {
      token: 'FLUX_GITHUB_TOKEN',
    }
  ),
  slackAddress: extrenalsecret(
    {
      name: 'slack-url',
      namespace: $._metadata.namespace,
    },
    'doppler-auth-api',
    {
      address: 'FLUX_SLACK_URL',
    }
  ),

  provider: {
    apiVersion: 'notification.toolkit.fluxcd.io/v1beta1',
    kind: 'Provider',
    metadata: $._metadata {
      name: 'slack',
    },
    spec: {
      type: 'slack',
      channel: 'deployments',
      secretRef: {
        name: 'slack-url',
      },
    },
  },

  alert: {
    apiVersion: 'notification.toolkit.fluxcd.io/v1beta1',
    kind: 'Alert',
    metadata: $._metadata {
      name: 'all-deployments',
    },
    spec: {
      providerRef: {
        name: 'slack',
      },
      // eventSeverity: "error",
      eventSeverity: 'info',
      eventSources: [
        {
          kind: 'GitRepository',
          name: '*',
        },
        {
          kind: 'Kustomization',
          name: '*',
        },
      ],
    },
  },

  receiver: {
    apiVersion: 'notification.toolkit.fluxcd.io/v1beta1',
    kind: 'Receiver',
    metadata: $._metadata {
      name: 'github-receiver',
    },
    spec: {
      type: 'github',
      events: ['ping', 'push'],
      secretRef: {
        name: 'github-webhook-token',
      },
      resources: [{
        apiVersion: 'source.toolkit.fluxcd.io/v1beta1',
        kind: 'GitRepository',
        name: 'ankhmorpork',
      }],
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
