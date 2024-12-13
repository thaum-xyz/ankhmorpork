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
  timezone: 'UTC',
  ingress: {
    domain: '',
    className: 'nginx',
    annotations: {
      'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
    },
  },
  zwaveSupport: false,
  hostNetwork: false,
  storage: {
    data: {
      pvcSpec: {
        // storageClassName: 'local-path',
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '2Gi',
          },
        },
      },
    },
    backups: {
      pvcSpec: {
        //  accessModes: ['ReadWriteMany'],
        //  resources: {
        //    requests: {
        //      storage: '1Gi',
        //    },
        //  },
      },
    },
  },
  // TODO: Consider creting an operator just to handle this part
  apiTokenSecretKeySelector: {},
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
        targetPort: $.statefulSet.spec.template.spec.containers[0].ports[0].name,
        port: 8123,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  [if std.objectHas(params, 'storage') && std.objectHas(params.storage, 'backups') && std.objectHas(params.storage.backups, 'pvcSpec') && std.length(params.storage.backups.pvcSpec) > 0 then 'backupsPVC']: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: $._metadata.name + '-backups',
    },
    spec: $._config.storage.backups.pvcSpec,
  },

  jobPull: {
    # Kubernetes job to download new image
    # This works together with kuik and preStop sleep lifecycle hook
    apiVersion: "batch/v1",
    kind: "Job",
    metadata: $._metadata {
      name: "pre-pull-image",
    },
    spec: {
      ttlSecondsAfterFinished: 1800,
      template: {
        spec: {
          containers: [{
            name: "prepull",
            image: $._config.image,
            command: ["sleep", "1"],
          }],
          restartPolicy: "Never",
        },
      },
    },
  },

  statefulSet: {
    local health = {
      name: "healthcheck",
      image: $._config.image,
      command: ["sh", "-c", "echo 'OK' > /config/www/healthz"],
      imagePullPolicy: 'IfNotPresent',
      resources: {
        requests: {
          cpu: "10m",
          memory: "10Mi",
        },
        limits: {
          cpu: "10m",
          memory: "10Mi",
        },
      },
      securityContext: {
        runAsUser: 0,
      },
      volumeMounts: [{
          mountPath: '/config',
          name: $._metadata.name + '-config',
      }]
    },

    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'TZ',
        value: $._config.timezone,
      }],
      preStop: {
        # Time to wait before job downloading new image completes
        sleep: 240,
      },
      ports: [{
        containerPort: 8123,
        name: 'http',
      }],
      startupProbe: {
        httpGet: {
          path: '/',
          port: 'http',
          scheme: 'HTTP',
        },
        failureThreshold: 120,
        periodSeconds: 2,
      },
      readinessProbe: {
        httpGet: {
          path: '/',
          port: 'http',
          scheme: 'HTTP',
        },
        initialDelaySeconds: 5,
        failureThreshold: 5,
        timeoutSeconds: 10,
      },
      livenessProbe: {
        httpGet: {
          path: '/local/healthz',
          port: 'http',
          scheme: 'HTTP',
        },
        initialDelaySeconds: 5,
        failureThreshold: 5,
        timeoutSeconds: 10,
      },
      securityContext: {
        privileged: $._config.zwaveSupport,
      },
      volumeMounts: [
        {
          mountPath: '/config',
          name: $._metadata.name + '-config',
        },{
          mountPath: '/config/backups',
          name: 'backups',
        }
      ],
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
          initContainers: [health],
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          hostNetwork: $._config.hostNetwork,
          terminationGracePeriodSeconds: 300,
          volumes: [
            if std.objectHas(params, 'storage') && std.objectHas(params.storage, 'backups') && std.objectHas(params.storage.backups, 'pvcSpec') && std.length(params.storage.backups.pvcSpec) > 0 then
              {
                name: 'backups',
                persistentVolumeClaim: {
                  claimName: $.backupsPVC.metadata.name,
                },
              }
            else
              {
                name: 'backups',
                emptyDir: {},
              },
          ],
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: $._metadata.name + '-config',
        },
        spec: $._config.storage.data.pvcSpec,
      }],
    },
  },

  [if std.objectHas(params, 'apiTokenSecretKeySelector') && std.length(params.ingress.domain) > 0 then 'serviceMonitor']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: [{
        interval: '90s',
        port: $.service.spec.ports[0].name,
        path: '/api/prometheus',
        bearerTokenSecret: $._config.apiTokenSecretKeySelector,
      }],
      selector: {
        matchLabels: $._config.selectorLabels,
      },
    },
  },

  [if std.objectHas(params, 'apiTokenSecretKeySelector') && std.length(params.ingress.domain) > 0 then 'prometheusRule']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata,
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
          expr: 'up{job="homeassistant"} == 0',
          'for': '30m',
          labels: {
            priority: 'P1',
            severity: 'critical',
          },
        }],
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
