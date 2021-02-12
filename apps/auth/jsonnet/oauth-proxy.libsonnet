local defaults = {
  local defaults = self,
  name: 'oauth2-proxy',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '5m', memory: '13Mi' },
    limits: { cpu: '15m', memory: '30Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'proxy',
    'app.kubernetes.io/part-of': 'auth',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  replicas: 1,
  domain: '',
  encryptedSecretsData: error 'must provide encryptedSecretsData',
};

function(params) {
  local o = self,
  config:: defaults + params,
  // Safety check
  assert std.isObject(o.config.resources),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: o.config.name,
      namespace: o.config.namespace,
      labels: o.config.commonLabels,
    },
  },

  creds: o.config.encryptedSecretsData,

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: o.config.name,
      namespace: o.config.namespace,
      labels: o.config.commonLabels,
    },
    spec: {
      ports: [{
        name: 'http',
        targetPort: o.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 4180,
      }],
      selector: o.config.selectorLabels,
      clusterIP: 'None',
    },
  },

  deployment: {
    local c = {
      name: o.config.name,
      image: o.config.image,
      imagePullPolicy: 'IfNotPresent',
      args: [  // TODO: costomize
        '--provider=google',
        '--email-domain=krupa.net.pl',
        '--cookie-domain=.ankhmorpork.thaum.xyz',
        '--whitelist-domain=.ankhmorpork.thaum.xyz',
        '--pass-host-header=true',
        '--set-xauthrequest=true',
        '--pass-basic-auth=false',
        '--http-address=0.0.0.0:4180',
      ],
      envFrom: [{
        secretRef: {
          name: o.creds.metadata.name,
        },
      }],
      ports: [{
        containerPort: 4180,
        name: 'http',
      }],
      resources: o.config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: o.config.name,
      namespace: o.config.namespace,
      labels: o.config.commonLabels,
    },
    spec: {
      replicas: o.config.replicas,
      selector: { matchLabels: o.config.selectorLabels },
      template: {
        metadata: { labels: o.config.commonLabels },
        spec: {
          affinity: (import '../../../lib/podantiaffinity.libsonnet').podantiaffinity(o.config.name),
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: o.serviceAccount.metadata.name,
        },
      },
    },
  },

  ingress: if o.config.ingressDomain != '' then {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: {
      name: o.config.name,
      namespace: o.config.namespace,
      labels: o.config.commonLabels,
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: o.config.name + '-tls',
        hosts: [o.config.ingressDomain],
      }],
      rules: [{
        host: o.config.ingressDomain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: o.config.name,
                port: {
                  name: o.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },


}
