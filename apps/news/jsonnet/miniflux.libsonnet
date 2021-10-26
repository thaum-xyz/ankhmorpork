local defaults = {
  local defaults = self,
  name: 'miniflux',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    //requests: { cpu: '200m', memory: '800Mi' },
    //limits: { cpu: '400m', memory: '1600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'miniflux',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'miniflux',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  configEnvs: {},
  postgresCreds: {},
  domain: '',
};

function(params) {
  local m = self,
  _config:: defaults + params,
  _metadata:: {
    name: m._config.name,
    namespace: m._config.namespace,
    labels: m._config.commonLabels,
  },
  // Safety check
  //assert std.isObject(m._config.resources),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: m._metadata,
  },

  postgresCreds: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: m._metadata {
      name: 'postgres-creds',
    },
    data: m._config.postgresCreds,
    // POSTGRES_DB
    // POSTGRES_USER
    // POSTGRES_PASSWORD
  },

  config: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: m._metadata,
    data: m._config.configEnvs,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: m._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: m.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 8080,
      }],
      selector: m._config.selectorLabels,
    },
  },

  deployment: {
    local c = {
      name: m._config.name,
      image: m._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'DATABASE_URL',
        value: 'postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@$(POSTGRES_SVC)/$(POSTGRES_DB)?sslmode=disable',
      }],
      envFrom: [
        {
          secretRef: {
            name: m.postgresCreds.metadata.name,
          },
        },
        {
          secretRef: {
            name: m.config.metadata.name,
          },
        },
      ],
      ports: [{
        containerPort: 8080,
        name: 'http',
      }],
      resources: m._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      selector: { matchLabels: m._config.selectorLabels },
      template: {
        metadata: {
          labels: m._config.commonLabels,
          annotations: {
            'checksum.config/md5': std.md5(std.toString(m._config.configEnvs)),
          },
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: m.serviceAccount.metadata.name,
        },
      },
    },
  },

  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: m._metadata {
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: m._config.name + '-tls',
        hosts: [m._config.domain],
      }],
      rules: [{
        host: m._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: m._config.name,
                port: {
                  name: m.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },
}
