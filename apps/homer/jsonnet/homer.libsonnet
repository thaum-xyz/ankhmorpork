local defaults = {
  local defaults = self,
  name: 'homer',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '1m', memory: '5Mi' },
    limits: { cpu: '10m', memory: '10Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'homer',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'homer',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  replicas: 1,
  domain: '',
  configData: error 'must provide configData',
};

function(params) {
  local h = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(h._config.resources),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: h._config.name,
      namespace: h._config.namespace,
      labels: h._config.commonLabels,
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: h._config.name,
      namespace: h._config.namespace,
      labels: h._config.commonLabels,
    },
    spec: {
      ports: [{
        name: 'http',
        targetPort: h.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 8080,
      }],
      selector: h._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  configmap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: h._config.name + '-config',
      namespace: h._config.namespace,
      labels: h._config.commonLabels,
    },
    data: {
      'config.yml': h._config.configData,
    },
  },

  deployment: {
    local c = {
      name: h._config.name,
      image: h._config.image,
      imagePullPolicy: 'IfNotPresent',
      ports: [{
        containerPort: 8080,
        name: 'http',
      }],
      volumeMounts: [{
        mountPath: '/www/assets/config.yml',
        name: 'config',
        subPath: 'config.yml',
      }],
      resources: h._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: h._config.name,
      namespace: h._config.namespace,
      labels: h._config.commonLabels,
    },
    spec: {
      replicas: h._config.replicas,
      selector: { matchLabels: h._config.selectorLabels },
      template: {
        metadata: {
          annotations: {
            'checksum.config/md5': std.md5(h._config.configData),
          },
          labels: h._config.commonLabels,
        },
        spec: {
          affinity: (import '../../../lib/podantiaffinity.libsonnet').podantiaffinity(h._config.name),
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: h.serviceAccount.metadata.name,
          volumes: [{
            name: 'config',
            configMap: {
              name: h.configmap.metadata.name,
            },
          }],
        },
      },
    },
  },


  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: {
      name: h._config.name,
      namespace: h._config.namespace,
      labels: h._config.commonLabels,  // + { probe: "enabled" }
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: h._config.name + '-tls',
        hosts: [h._config.domain],
      }],
      rules: [{
        host: h._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: h._config.name,
                port: {
                  name: h.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },
}
