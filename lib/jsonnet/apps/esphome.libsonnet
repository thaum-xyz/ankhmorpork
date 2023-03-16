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
  domain: '',
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
  local e = self,
  _config:: defaults + params,
  _metadata:: {
    name: e._config.name,
    namespace: e._config.namespace,
    labels: e._config.commonLabels,
  },
  // Safety check
  assert std.isObject(e._config.resources),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: e._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: e._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: e.statefulset.spec.template.spec.containers[0].ports[0].name,
        port: 6052,
      }],
      selector: e._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  statefulset: {
    local c = {
      name: e._config.name,
      image: e._config.image,
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
        name: e._config.storage.name,
      }],
      resources: e._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: e._metadata,
    spec: {
      serviceName: e.service.metadata.name,
      replicas: 1,
      selector: { matchLabels: e._config.selectorLabels },
      template: {
        metadata: {
          labels: e._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: e.serviceAccount.metadata.name,
          hostNetwork: e._config.hostNetwork,
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: e._config.storage.name,
        },
        spec: e._config.storage.pvcSpec,
      }],
    },
  },

  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: {
      name: e._config.name,
      namespace: e._config.namespace,
      labels: e._config.commonLabels,  // + { probe: "enabled" }
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: e._config.name + '-tls',
        hosts: [e._config.domain],
      }],
      rules: [{
        host: e._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: e._config.name,
                port: {
                  name: e.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },
}
