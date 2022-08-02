local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

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
        'kubernetes.io/ingress.class': 'nginx',
        'nginx.ingress.kubernetes.io/limit-rps': '100',
      },
    },
    spec: {
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
            max_over_time(gotk_reconcile_condition{status=~"False|Unknown",type="Ready"}[3m]) == 1
          |||,
          'for': '10m',
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
  githubToken: sealedsecret(
    {
      name: 'github-webhook-token',
      namespace: $._metadata.namespace,
    },
    {
      token: 'AgBY2JKgm87ol6rvnhDKyq8gJmTQ1Ba+mGRDeBTbtg1mQ+ylbK5iwGp+BHt9asywIxbaC1H+4Dq6Ozr1j2kzDO57IDgCO79z8LKmTsPLuu/9C6CQWflbuPxob5rRbeoMF96AlhhbRJxhSeD4c2n5tvT30tzLQyLSNxl+GZ+ZnVk3td2vS4j+MFzJq5bWeZ5w1xi6tMGZHHdZ3kM3bduGNG8MvtfcxrhXmd5HNZL4XNATQms3MUzM2ms9e7j4XRUJCvmqnuT3HKdUCW+LL57dpMqXeiQBGDvwvzmv/P5TGoe3LMlEpWm0Pq8s1TrHlG5MXK0+5npglcFLDHfiyXwVab/MlPa7Sa5d4GUOngdUcWRKpTQbWDTH8JDdHCoG3voZml4gpAhzHVNx66GID6/wFLLk9kEXyEQ17hongTavT1gOHMse225yOftG7nyAEpvSSZYDcEyHzfIWvkC+l0Vv8acceCuEmJjTSxvpxge9OCZ7BhVrA9bbBUOf7/ea25mBpIvTFAujoCwegAEFbwOYx8PZRviDrgWOc3ea6Y0k1wlYtUjAKCHkesKFPynEFvVwNbDw9f0Q23M1jI51Xzsm5osHZuKxGi11yl/+oWBWlqAjyiv7r+2f5zVE3cqzqO5zmCydMkrMhQADlOmQ0qV4eiqU05EcdBm05270g8NuDuZkT9/0BTVJsnlILYr+2QAUmAkPDBb6KU8WcC6cvJXHWoi6qkTgmBqyfT/P0af2umVJTcdhYps3KGX8',
    }
  ),
  slackAddress: sealedsecret(
    {
      name: 'slack-url',
      namespace: $._metadata.namespace,
    },
    {
      address: 'AgB3z3Wy9Qq/g4AWs0XSinYAaTnqr0uIODOZWna9yDmqda+MD8dkxmrtCpE/NIFnYBxhQuh9m181zDSUntXtUZ10eR9QmTyFwQgk7GZ9g+xbK1kd/gPOg+omymgfXkKxp1HWNPbBGDLPU0BYHMPtzfLoG+Vy+tDHacd2xS36YLEhFsn89LjzwdMqBFdnTMi5qe45hmu2+CtzhKeIUX8jtQz89HN8gCTpTj8DqkcyvS9iGPN5yEGlesOqMEwDXILKUAhy9rE7Htr9RVSXnLzl2bpJwSkgoC3iG9pbm+zaHkXffk+OxLzRJTqKgQqJ7gMOzyb8HIFzM/djTYV2dJTaQDzyceNYHrW0kmMbFjqTdrT922ess2k/nUFfNO7rLwtJ4ONxu8z3XWfMZCTGzWospc3XDGVoIrLOwOnNifvkz49OJrAJPtj0HQQ0t5eVXaw5sF2HhUoA0ENlYiEU124syFHCmCDA8uqoedspswX8appm9zkYkxKshlZ90Rfawj7AJfuJxUkKUF7lGY/zfLyEruScayucPQ8yTw+JUj192Gal4t5oErrdoG9PL2THLhHaKl1Gdyo643S9DaLYMfLomNe/68nA5kFy9CScL3vHlHrVT921CGxrECkHYOJg8h0g8YrLzAuhV1cTHfG8TBV4FNkkxhQrvKg33CmE9bAJrdLs0S7TS5ko31T0rnBe2cDyMX5BnRuBCHih08KApaI2CcnzsEH9GEb0fRszVZgaGlP2Q69+LNxoYVuZofdmAnfJfK/7HPg+FlLGSciV1MtON/mipWzKITvfgTLgtKrk+EFG',
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
