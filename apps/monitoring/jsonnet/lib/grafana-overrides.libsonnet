{
  service+: {
    spec+: {
      type: 'ClusterIP',
    },
  },
  dashboardSources:: null,
  dashboardDefinitions:: null,
  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      labels: {
        'app.kubernetes.io/name': 'grafana',
        'app.kubernetes.io/component': 'grafana',
        'app.kubernetes.io/part-of': 'kube-prometheus',
      },
      name: 'grafana',
      namespace: 'monitoring',
    },
    spec: {
      replicas: 1,
      selector: {
        matchLabels: {
          'app.kubernetes.io/name': 'grafana',
          'app.kubernetes.io/component': 'grafana',
          'app.kubernetes.io/part-of': 'kube-prometheus',
        },
      },
      template: {
        metadata: {
          labels: {
            'app.kubernetes.io/name': 'grafana',
            'app.kubernetes.io/component': 'grafana',
            'app.kubernetes.io/part-of': 'kube-prometheus',
          },
        },
        spec: {
          containers: [
            {
              env: [
                { name: 'GF_SERVER_ROOT_URL', value: 'https://grafana.ankhmorpork.thaum.xyz' },
                { name: 'GF_AUTH_ANONYMOUS_ENABLED', value: 'false' },
                { name: 'GF_AUTH_DISABLE_LOGIN_FORM', value: 'true' },
                { name: 'GF_AUTH_SIGNOUT_REDIRECT_URL', value: 'https://auth.ankhmorpork.thaum.xyz/oauth2?logout=true' },
                { name: 'GF_AUTH_BASIC_ENABLED', value: 'false' },
                { name: 'GF_AUTH_PROXY_AUTO_SIGN_UP', value: 'false' },
                { name: 'GF_AUTH_PROXY_ENABLED', value: 'true' },
                { name: 'GF_AUTH_PROXY_HEADER_NAME', value: 'X-Auth-Request-Email' },
                { name: 'GF_AUTH_PROXY_HEADER_PROPERTY', value: 'username' },
                { name: 'GF_AUTH_PROXY_HEADERS', value: 'Email:X-Auth-Request-Email' },
                { name: 'GF_SNAPSHOTS_EXTERNAL_ENABLED', value: 'false' },
              ],
              image: 'grafana/grafana:7.3.7',
              //image: $.values.grafana.image,
              name: 'grafana',
              ports: [{
                containerPort: 3000,
                name: 'http',
              }],
              resources: {
                limits: { cpu: '400m', memory: '200Mi' },
                requests: { cpu: '100m', memory: '100Mi' },
              },
              volumeMounts: [
                {
                  mountPath: '/var/lib/grafana',
                  name: 'grafana-storage',
                },
                {
                  mountPath: '/etc/grafana/provisioning/datasources',
                  name: 'grafana-datasources',
                },
              ],
            },
          ],
          securityContext: {
            runAsNonRoot: true,
            runAsUser: 472,
          },
          nodeSelector: {
            'kubernetes.io/os': 'linux',
          },
          serviceAccountName: 'grafana',
          volumes: [
            {
              name: 'grafana-storage',
              persistentVolumeClaim: {
                claimName: 'grafana-data',
              },
            },
            {
              name: 'grafana-datasources',
              secret: {
                secretName: 'grafana-datasources',
              },
            },
          ],
        },
      },
    },
  },

  pvc: {
    kind: 'PersistentVolumeClaim',
    apiVersion: 'v1',
    metadata: {
      name: 'grafana-data',
      namespace: 'monitoring',
      annotations: {
        'volume.beta.kubernetes.io/storage-class': 'longhorn',
      },
    },
    spec: {
      storageClassName: 'longhorn',
      accessModes: ['ReadWriteMany'],
      resources: {
        requests: {
          storage: '60Mi',
        },
      },
    },
  },

  ingress: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: {
      name: 'grafana',
      namespace: 'monitoring',
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
        'nginx.ingress.kubernetes.io/auth-url': 'https://auth.ankhmorpork.thaum.xyz/oauth2/auth',
        'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.ankhmorpork.thaum.xyz/oauth2/start?rd=$scheme://$host$escaped_request_uri',
        'nginx.ingress.kubernetes.io/auth-response-headers': 'X-Auth-Request-Email',
      },
    },
    spec: {
      tls: [{
        hosts: ['grafana.ankhmorpork.thaum.xyz'],
        secretName: 'grafana-tls',
      }],
      rules: [{
        host: 'grafana.ankhmorpork.thaum.xyz',
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: 'grafana',
                port: { name: 'http' },
              },
            },
          }],
        },
      }],
    },
  },


}
