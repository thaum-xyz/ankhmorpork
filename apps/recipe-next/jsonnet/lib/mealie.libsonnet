local defaults = {
  local defaults = self,
  name: 'mealie',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  //credentialsSecretRef: error 'must provide credentials Secret name',
  api: {
    image: error 'must provide API image',
    resources: {
      //requests: { cpu: '90m', memory: '150Mi' },
      //limits: { cpu: '200m', memory: '300Mi' },
    },
  },
  frontend: {
    image: error 'must provide frontend image',
    resources: {
      //requests: { cpu: '90m', memory: '150Mi' },
      //limits: { cpu: '200m', memory: '300Mi' },
    },
  },
  commonLabels:: {
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/part-of': 'mealie',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  domain: '',
  storage: {
    name: defaults.name,
    pvcSpec: {
      accessModes: ['ReadWriteMany'],
      resources: {
        requests: {
          storage: '1Gi',
        },
      },
    },
  },
};

function(params) {
  local m = self,
  _config:: defaults + params + {
    api: defaults.api + params.api,
    frontend: defaults.frontend + params.frontend,
  },
  // Safety check
  assert std.isObject($._config.api.resources),
  assert std.isObject($._config.frontend.resources),

  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  // COMMON DEFINITIONS
  common: {
    pvc: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: m._metadata {
        name: $._config.storage.name,
      },
      spec: $._config.storage.pvcSpec,
    },


  },

  // FRONTEND DEFINITIONS
  frontend: {
    _metadata:: m._metadata {
      name: 'frontend',
      labels: $._config.commonLabels {
        'app.kubernetes.io/component': 'frontend',
      },
    },
    _selectorLabels:: $._config.selectorLabels {
      'app.kubernetes.io/component': 'frontend',
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
          port: 80,
        }],
        selector: $._selectorLabels,
        clusterIP: 'None',
      },
    },

    deployment: {
      local c = {
        name: $.frontend._metadata.name,
        image: $._config.frontend.image,
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
          containerPort: 80,
          name: 'http',
        }],
        readinessProbe: {
          httpGet: {
            path: '/api/debug/version',
            port: 'http',
            scheme: 'HTTP',
          },
          initialDelaySeconds: 5,
          failureThreshold: 5,
          timeoutSeconds: 10,
        },
        volumeMounts: [{
          mountPath: '/app/data',
          name: 'appdata',
        }],
        resources: $._config.frontend.resources,
      },

      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: $.frontend._metadata,
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
            serviceAccountName: $.frontend.serviceAccount.metadata.name,
            volumes: [{
              name: 'appdata',
              persistentVolumeClaim: {
                claimName: $.common.pvc.metadata.name,
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


  },

  // API DEFINITIONS
  api: {
    _metadata:: m._metadata {
      name: 'api',
      labels: $._config.commonLabels {
        'app.kubernetes.io/component': 'api',
      },
    },
    _selectorLabels:: $._config.selectorLabels {
      'app.kubernetes.io/component': 'api',
    },

    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      automountServiceAccountToken: false,
      metadata: $._metadata,
    },

    /*service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: $._metadata,
      spec: {
        ports: [{
          name: 'http',
          targetPort: $.api.deployment.spec.template.spec.containers[0].ports[0].name,
          port: 80,
        }],
        selector: $._config.selectorLabels,
        clusterIP: 'None',
      },
    },*/

  },


}
