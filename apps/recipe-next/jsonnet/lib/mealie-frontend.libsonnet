local defaults = {
  local defaults = self,
  name: 'frontend',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  //credentialsSecretRef: error 'must provide credentials Secret name',
  image: error 'must provide frontend image',
  resources: {
    //requests: { cpu: '90m', memory: '150Mi' },
    //limits: { cpu: '200m', memory: '300Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'frontend',
    'app.kubernetes.io/part-of': 'mealie',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  apiUrl: 'http://api.' + defaults.namespace + '.svc:9000',
  domain: '',
  storage: {
    // PVC is created as part of API deployment
    name: 'data',
  },
};

function(params) {
  local m = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject($._config.resources),

  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: $._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: $.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 3000,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  deployment: {
    local c = {
      name: $._metadata.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'API_URL',
        value: $._config.apiUrl,
      }],
      /*envFrom: [{
        secretRef: {
          name: $._config.credentialsSecretRef,
        },
      }],*/
      ports: [{
        containerPort: 3000,
        name: 'http',
      }],
      /*readinessProbe: {
        httpGet: {
          path: '/api/debug/version',
          port: 'http',
          scheme: 'HTTP',
        },
        initialDelaySeconds: 5,
        failureThreshold: 5,
        timeoutSeconds: 10,
      },*/
      volumeMounts: [{
        mountPath: '/app/data',
        name: 'appdata',
      }],
      resources: $._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          labels: $._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          volumes: [{
            name: 'appdata',
            persistentVolumeClaim: {
              // PVC is created as part of API deployment
              claimName: $._config.storage.name,
            },
          }],
        },
      },
    },
  },


  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: $._config.name + '-tls',
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
                name: $._config.name,
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
