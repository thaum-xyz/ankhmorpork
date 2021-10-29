{
  _config:: {
    version: '2.31.0',
    image: 'quay.io/prometheus/prometheus:v2.31.0',
    commonLabels: {},
    selectorLabels: {},
    name: 'rw-proxy',
    namespace: 'monitoring',
    resources: {},
    domain: 'push.ankhmorpork.thaum.xyz',
    remoteWriteAuth: '',
  },

  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  prometheus: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'Prometheus',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      version: $._config.version,
      image: $._config.image,
      podMetadata: {
        labels: $._config.commonLabels,
      },
      externalLabels: {
        prometheus: 'proxy',
      },
      retention: '3h',  // CHECK
      serviceAccountName: 'prometheus-rw-proxy',
      // Deselect all CR selectors
      podMonitorSelector: '',
      podMonitorNamespaceSelector: '',
      probeSelector: '',
      probeNamespaceSelector: '',
      ruleNamespaceSelector: '',
      ruleSelector: '',
      serviceMonitorSelector: '',
      serviceMonitorNamespaceSelector: '',
      nodeSelector: { 'kubernetes.io/os': 'linux' },
      resources: $._config.resources,
      alerting: {},
      securityContext: {
        runAsUser: 1000,
        runAsNonRoot: true,
        fsGroup: 2000,
      },
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [
        { name: 'web', targetPort: 'web', port: 9090 },
      ],
      selector: $._config.selectorLabels,
    },
  },

  ingress: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
        'nginx.ingress.kubernetes.io/auth-type': 'basic',
        'nginx.ingress.kubernetes.io/auth-secret': 'prometheus-remote-write-auth',
      },
    },
    spec: {
      tls: [{
        hosts: [$._config.domain],
        secretName: $._metadata.name + '-tls',
      }],
      rules: [{
        host: $._config.domain,
        http: {
          paths: [
            {
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: $.service.metadata.name,
                  port: {
                    name: 'web',
                  },
                },
              },
            },
          ],
        },
      }],
    },
  },
  remoteWriteAuth: sealedsecret(
    {
      name: 'prometheus-remote-write-auth',
      namespace: $._metadata.namespace,
    },
    {
      auth: $._config.remoteWriteAuth,
    },
  ),
}
