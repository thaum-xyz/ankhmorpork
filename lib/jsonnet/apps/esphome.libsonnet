local defaults = {
  local defaults = self,
  name: 'esphome',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '120m', memory: '200Mi' },
    limits: { cpu: '400m', memory: '600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'esphome',
    'app.kubernetes.io/version': defaults.version,
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  ingress: {
    domain: '',
    className: 'nginx',
    annotations: {
      'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
    },
  },
  hostNetwork: true,
  storage: {
    name: 'esphome-data',
    pvcSpec: {
      // storageClassName: 'local-path',
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '200Mi',
        },
      },
    },
  },
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  // Safety check
  assert std.isObject($._config.resources),

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
        targetPort: $.statefulset.spec.template.spec.containers[0].ports[0].name,
        port: 6052,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  statefulset: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'ESPHOME_DASHBOARD_USE_PING',
        value: 'true',
      }],
      ports: [{
        containerPort: 6052,
        name: 'http',
      }],
      volumeMounts: [{
        mountPath: '/config',
        name: $._config.storage.name,
      }],
      resources: $._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: $._metadata,
    spec: {
      serviceName: $.service.metadata.name,
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
          hostNetwork: $._config.hostNetwork,
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: $._config.storage.name,
        },
        spec: $._config.storage.pvcSpec,
      }],
    },
  },

  [if std.objectHas(params, 'ingress') && std.objectHas(params.ingress, 'domain') && std.length(params.ingress.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: $._config.ingress.annotations,
    },
    spec: {
      ingressClassName: $._config.ingress.className,
      tls: [{
        secretName: $._config.name + '-tls',
        hosts: [$._config.ingress.domain],
      }],
      rules: [{
        host: $._config.ingress.domain,
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
