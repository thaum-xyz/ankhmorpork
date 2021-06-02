local defaults = {
  local defaults = self,
  name: 'homeassistant',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '200m', memory: '800Mi' },
    limits: { cpu: '400m', memory: '1600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'homeassistant',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'homeassistant',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  domain: '',
  zwaveSupport: false,
  hostNetwork: false,
  pvcSpec: '',
  // TODO: Consider creting an operator just to handle this part
  apiTokenSecretKeySelector: {},
};

function(params) {
  local h = self,
  _config:: defaults + params,
  _metadata:: {
    name: h._config.name,
    namespace: h._config.namespace,
    labels: h._config.commonLabels,
  },
  // Safety check
  assert std.isObject(h._config.resources),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: h._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: h._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: h.statefulSet.spec.template.spec.containers[0].ports[0].name,
        port: 8123,
      }],
      selector: h._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  statefulSet: {
    local c = {
      name: h._config.name,
      image: h._config.image,
      imagePullPolicy: 'IfNotPresent',
      ports: [{
        containerPort: 8123,
        name: 'http',
      }],
      readinessProbe: {
        httpGet: {
          path: '/',
          port: 'http',
          scheme: 'HTTP',
        },
        initialDelaySeconds: 60,
        failureThreshold: 5,
        timeoutSeconds: 10,
      },
      securityContext: {
        privileged: h._config.zwaveSupport,
      },
      volumeMounts: [{
        mountPath: '/config',
        name: 'config',
      }],
      resources: h._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: h._metadata,
    spec: {
      serviceName: h.service.metadata.name,
      replicas: 1,
      selector: { matchLabels: h._config.selectorLabels },
      template: {
        metadata: {
          labels: h._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: h.serviceAccount.metadata.name,
          hostNetwork: h._config.hostNetwork,
          volumes: [{
            name: 'config',
            // Add conditional based on pvcSpec
            persistentVolumeClaim: {
              claimName: h.pvc.metadata.name,
            },
          }],
        },
      },
    },
  },

  [if std.objectHas(params, 'pvcSpec') && std.length(params.domain) > 0 then 'pvc']: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: h._metadata {
      name: 'config',
    },
    spec: h._config.pvcSpec,
  },

  [if std.objectHas(params, 'apiTokenSecretKeySelector') && std.length(params.domain) > 0 then 'serviceMonitor']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: h._metadata,
    spec: {
      endpoints: [{
        interval: '90s',
        port: h.service.spec.ports[0].name,
        path: '/api/prometheus',
        bearerTokenSecret: h._config.apiTokenSecretKeySelector,
      }],
      selector: {
        matchLabels: h._config.selectorLabels,
      },
    },
  },

  [if std.objectHas(params, 'apiTokenSecretKeySelector') && std.length(params.domain) > 0 then 'prometheusRule']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: h._metadata,
    // TODO: Create HomeAssistant monitoring mixin
    // FIXME: Create SLO?
    spec: {
      groups: [{
        name: 'homeassistant.alerts',
        rules: [{
          alert: 'HomeAssistantDown',
          annotations: {
            description: 'Home Assistant instance {{ $labels.instance }} is down',
            summary: 'Home Assistant is down',
          },
          expr: 'up{job=~"homeassistant.*"} == 0',
          'for': '30m',
          labels: {
            priority: 'P1',
            severity: 'critical',
          },
        }],
      }],
    },
  },

  [if std.objectHas(params, 'domain') && std.length(params.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: h._metadata {
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
