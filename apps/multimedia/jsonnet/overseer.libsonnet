local defaults = {
  local defaults = self,
  name: 'overseer',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '50m', memory: '250Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'overseer',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  domain: '',
  storage: {
    name: 'appdata',
    pvcSpec: {
      storageClassName: 'local-path',
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '600Mi',
        },
      },
    },
  },
};

function(params) {
  local o = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(o._config.resources),

  _metadata:: {
    name: o._config.name,
    namespace: o._config.namespace,
    labels: o._config.commonLabels,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: o._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: o._metadata,
    spec: {
      ports: [{
        name: o.statefulset.spec.template.spec.containers[0].ports[0].name,
        targetPort: o.statefulset.spec.template.spec.containers[0].ports[0].name,
        port: o.statefulset.spec.template.spec.containers[0].ports[0].containerPort,
      }],
      selector: o._config.selectorLabels,
    },
  },

  statefulset: {
    local c = {
      name: o._config.name,
      image: o._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [
        {
          name: 'TZ',
          value: 'Europe/Berlin',
        },
        {
          name: 'LOG_LEVEL',
          value: 'debug',
        },
      ],
      ports: [{
        containerPort: 5055,
        name: 'http',
      }],
      readinessProbe: {
        httpGet: {
          path: '/api/v1/status',
          port: c.ports[0].name,
        },
        initialDelaySeconds: 10,
        timeoutSeconds: 10,
        failureThreshold: 5,
      },
      volumeMounts: [
        {
          mountPath: '/app/config',
          name: o._config.storage.name,
        },
        {
          mountPath: '/app/config/logs',
          name: 'logs',
        },
      ],
      resources: o._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: o._metadata,
    spec: {
      replicas: 1,
      serviceName: o.service.metadata.name,
      selector: { matchLabels: o._config.selectorLabels },
      template: {
        metadata: {
          labels: o._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: o.serviceAccount.metadata.name,
          volumes: [{
            emptyDir: {},
            name: 'logs',
          }],
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: o._config.storage.name,
        },
        spec: o._config.storage.pvcSpec,
      }],
    },
  },

  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: {
      name: o._config.name,
      namespace: o._config.namespace,
      labels: o._config.commonLabels,  // + { probe: "enabled" }
      annotations: {
        'kubernetes.io/ingress.class': 'nginx',
        'cert-manager.io/cluster-issuer': 'letsencrypt-prod',  // TODO: customize
      },
    },
    spec: {
      tls: [{
        secretName: o._config.name + '-tls',
        hosts: [o._config.domain],
      }],
      rules: [{
        host: o._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: o._config.name,
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
