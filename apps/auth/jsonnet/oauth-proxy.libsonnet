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
  config:: defaults + params,
  // Safety check
  assert std.isObject($.config.resources),

  metadata:: {
    name: $.config.name,
    namespace: $.config.namespace,
    labels: $.config.commonLabels,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: $.metadata,
  },

  creds: $.config.encryptedSecretsData,

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $.metadata,
    spec: {
      ports: [
        {
          name: 'http',
          targetPort: $.deployment.spec.template.spec.containers[0].ports[0].name,
          port: 4180,
        },
        {
          name: 'metrics',
          targetPort: $.deployment.spec.template.spec.containers[0].ports[1].name,
          port: 8080,
        },
      ],
      selector: $.config.selectorLabels,
      clusterIP: 'None',
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $.metadata,
    spec: {
      selector: {
        matchLabels: $.config.selectorLabels,
      },
      endpoints: [
        { port: 'metrics', interval: '30s' },
      ],
    },
  },


  deployment: {
    local c = {
      name: $.config.name,
      image: $.config.image,
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
        '--metrics-address=0.0.0.0:8080',
      ],
      envFrom: [{
        secretRef: {
          name: $.creds.metadata.name,
        },
      }],
      ports: [
        {
          containerPort: 4180,
          name: 'http',
        },
        {
          containerPort: 8080,
          name: 'metrics',
        },
      ],
      resources: $.config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $.metadata,
    spec: {
      replicas: $.config.replicas,
      selector: { matchLabels: $.config.selectorLabels },
      template: {
        metadata: { labels: $.config.commonLabels },
        spec: {
          affinity: (import '../../../lib/podantiaffinity.libsonnet').podantiaffinity($.config.name),
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
        },
      },
    },
  },

  ingress: if $.config.ingressDomain != '' then {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $.metadata {
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: $.config.name + '-tls',
        hosts: [$.config.ingressDomain],
      }],
      rules: [{
        host: $.config.ingressDomain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: $.config.name,
                port: {
                  name: $.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },


}
