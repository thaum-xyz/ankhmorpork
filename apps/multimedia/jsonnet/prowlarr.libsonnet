local defaults = {
  local defaults = self,
  name: 'prowlarr',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {},
  commonLabels:: {
    'app.kubernetes.io/name': 'prowlarr',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'prowlarr',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  storage: {
    config: {
      pvcSpec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '1Gi',
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
};

function(params) {
  local j = self,
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
        name: $.statefulset.spec.template.spec.containers[0].ports[0].name,
        targetPort: $.statefulset.spec.template.spec.containers[0].ports[0].name,
        port: $.statefulset.spec.template.spec.containers[0].ports[0].containerPort,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  [if std.objectHas(params, 'storage') && std.objectHas(params.storage, 'backups') && std.objectHas(params.storage.backups, 'pvcSpec') && std.length(params.storage.backups.pvcSpec) > 0 then 'backupsPVC']: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: $._metadata.name + '-backup',
    },
    spec: $._config.storage.backups.pvcSpec,
  },

  statefulset: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [{
        name: 'TZ',
        value: 'UTC',
      }],
      ports: [{
        containerPort: 9696,
        name: 'http',
      }],
      readinessProbe: {
        tcpSocket: { port: c.ports[0].containerPort },
        initialDelaySeconds: 0,
        periodSeconds: 60,
        failureThreshold: 3,
        timeoutSeconds: 1,
      },
      startupProbe: {
        tcpSocket: { port: c.ports[0].containerPort },
        initialDelaySeconds: 0,
        periodSeconds: 5,
        failureThreshold: 30,
        timeoutSeconds: 1,
      },
      volumeMounts: [
        {
          mountPath: '/config',
          name: 'config',
        },
        {
          mountPath: '/config/Backups',
          name: 'backup',
        },
      ],
      resources: $._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      selector: { matchLabels: $._config.selectorLabels },
      serviceName: $.service.metadata.name,
      template: {
        metadata: {
          annotations: {
            'kubectl.kubernetes.io/default-container': c.name,
          },
          labels: $._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,

          volumes: [
            if std.objectHas(params, 'storage') && std.objectHas(params.storage, 'backups') && std.objectHas(params.storage.backups, 'pvcSpec') && std.length(params.storage.backups.pvcSpec) > 0 then
              {
                name: 'backup',
                persistentVolumeClaim: {
                  claimName: $.backupsPVC.metadata.name,
                },
              }
            else
              {
                name: 'backup',
                emptyDir: {},
              },
          ],
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: 'config',
        },
        spec: $._config.storage.config.pvcSpec,
      }],
    },
  },
}
