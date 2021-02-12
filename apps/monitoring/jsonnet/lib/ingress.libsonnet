// TODO:
// - tls
// - "functional" and parametrized design
// - parametrized ingress annotations

local ingress(name, namespace, rules) = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'Ingress',
  metadata: {
    name: name,
    namespace: namespace,
    annotations: {
      'nginx.ingress.kubernetes.io/auth-type': 'basic',
      'nginx.ingress.kubernetes.io/auth-secret': 'basic-auth',
      'nginx.ingress.kubernetes.io/auth-realm': 'Authentication Required',
    },
  },
  spec: { rules: rules },
};

{
    // Configure External URL's per application
    alertmanager+: {
      alertmanager+: {
        spec+: {
          externalUrl: 'https://alertmanager.' + $.values.common.baseDomain,
        },
      },
      ingress: ingress(
        'alertmanager-main',
        $.values.common.namespace,
        [{
          host: 'alertmanager.' + $.values.common.baseDomain,
          http: {
            paths: [{
              backend: {
                service: {
                  name: 'alertmanager-main',
                  port: 'web',
                },
              },
            }],
          },
        }]
      ),
    },
    prometheus+: {
      prometheus+: {
        spec+: {
          externalUrl: 'https://prometheus.' + $.values.common.baseDomain,
        },
      },
      ingress: ingress(
        'alertmanager-main',
        $.values.common.namespace,
        [{
          host: 'prometheus.' + $.values.common.baseDomain,
          http: {
            paths: [{
              backend: {
                service: {
                  name: 'prometheus-k8s',
                  port: 'web',
                },
              },
            }],
          },
        }]
      ),
    },
    grafana+: {
      ingress: ingress(
        'grafana',
        $.values.common.namespace,
        [{
          host: 'grafana.' + $.values.common.baseDomain,
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: 'grafana',
                  port: 'http',
                },
              },
            }],
          },
        }],
      ),

    },
    {
    // Create basic auth secret - replace 'auth' file with your own
    ingress+:: {
      'basic-auth-secret': {
        apiVersion: 'v1',
        kind: 'Secret',
        metadata: {
          name: 'basic-auth',
          namespace: $.values.common.namespace,
        },
        data: { auth: std.base64(importstr 'auth') },
        type: 'Opaque',
      },
    },
  };

{ [name + '-ingress']: kp.ingress[name] for name in std.objectFields(kp.ingress) }
