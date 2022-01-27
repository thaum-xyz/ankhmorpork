local defaults = {
  local defaults = self,
  name: error 'must provide name',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  port: error 'must provide port',
  exporter: {
    image: 'ghcr.io/onedr0p/exportarr:v0.6.2',
    resources: {
      limits: {
        cpu: '50m',
        memory: '100Mi',
      },
      requests: {
        cpu: '1m',
        memory: '11Mi',
      },
    },
  },
  resources: {
    requests: {
      cpu: '60m',
      memory: '635Mi',
    },
  },
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': defaults.name,
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  storage: {
    name: defaults.name + '-backup',
    pvcSpec: {
      accessModes: ['ReadWriteMany'],
      resources: {
        requests: {
          storage: '1Gi',
        },
      },
    },
  },
  multimediaPVCName: error 'must provide multimediaPVCName',
  downloadsPVCName: 'downloads',
};

function(params) {
  local j = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject($._config.resources),
  assert std.isNumber($._config.port),

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
      ports: [
        {
          name: $.statefulset.spec.template.spec.containers[0].ports[0].name,
          targetPort: $.statefulset.spec.template.spec.containers[0].ports[0].name,
          port: $.statefulset.spec.template.spec.containers[0].ports[0].containerPort,
          protocol: "TCP",
        },{
          name: $.statefulset.spec.template.spec.containers[1].ports[0].name,
          targetPort: $.statefulset.spec.template.spec.containers[1].ports[0].name,
          port: $.statefulset.spec.template.spec.containers[1].ports[0].containerPort,
          protocol: "TCP",
        }
      ],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  serviceMonitor: {
    apiVersion: "monitoring.coreos.com/v1",
    kind: "ServiceMonitor",
    metadata: $._metadata,
    spec: {
      endpoints: [{
        port: $.statefulset.spec.template.spec.containers[1].ports[0].name,
      }],
      selector: {
        matchLabels: $._config.selectorLabels,
      },
    },
  },

  pvc: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      name: $._config.storage.name,
    },
    spec: $._config.storage.pvcSpec,
  },

  statefulset: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [
        {
          name: 'TZ',
          value: 'Europe/Berlin',
        },
        {
          name: 'PUID',
          value: '1000',
        },
        {
          name: 'GUID',
          value: '1000',
        },
      ],
      ports: [{
        containerPort: $._config.port,
        name: 'http',
      }],
      readinessProbe: {
        tcpSocket: { port: c.ports[0].name },
        initialDelaySeconds: 2,
        failureThreshold: 5,
        timeoutSeconds: 10,
      },
      startupProbe: {
        tcpSocket: { port: c.ports[0].name },
        initialDelaySeconds: 0,
        periodSeconds: 5,
        failureThreshold: 60,
        timeoutSeconds: 1,
      },
      volumeMounts: [
        {
          mountPath: '/config',
          name: 'config',
        },
        {
          mountPath: '/backup',
          name: 'backup',
        },
        {
          mountPath: '/multimedia',
          name: 'multimedia',
        },
        {
          mountPath: '/download/completed',
          name: 'downloads',
        },
      ],
      resources: $._config.resources,
    },

    local e = {
      args: ['exportarr', $._config.name],
      env: [
        {
          name: 'CONFIG',
          value: '/app/config.xml',
        },
        {
          name: 'URL',
          value: 'http://localhost',
        },
        {
          name: 'PORT',
          value: "9708",
        },
      ],
      image: $._config.exporter.image,
      name: 'exportarr',
      ports: [{
        containerPort: 9708,
        name: 'metrics',
      }],
      readinessProbe: {
        failureThreshold: 5,
        periodSeconds: 10,
        httpGet: {
          path: '/healthz',
          port: 'metrics',
        },
      },
      resources: $._config.exporter.resources,
      volumeMounts: [{
        mountPath: '/app',
        name: 'config',
        readOnly: true,
      }],
    },

    local init = {
      command: ['/bin/sh'],
      args: ['-c', "cd /config && unzip $(find /backup/scheduled -type f -exec stat -c '%n' {} + | sort -r | head -n1)"],
      image: 'quay.io/paulfantom/rsync',
      name: 'restore',
      volumeMounts: [
        {
          name: 'config',
          mountPath: '/config',
        },
        {
          name: 'backup',
          mountPath: '/backup',
          readOnly: true,
        },
      ],
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
            "kubectl.kubernetes.io/default-container": c.name,
          },
          labels: $._config.commonLabels,
        },
        spec: {
          initContainers: [init],
          containers: [c, e],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          volumes: [
            {
              name: 'config',
              emptyDir: {},  // TODO: This could be a volume temlate so restoring from backup on start wouldn't be needed
            },
            {
              name: 'backup',
              persistentVolumeClaim: {
                claimName: $.pvc.metadata.name,
              },
            },
            {
              name: 'multimedia',
              persistentVolumeClaim: {
                claimName: $._config.multimediaPVCName,
              },
            },
            {
              name: 'downloads',
              persistentVolumeClaim: {
                claimName: $._config.downloadsPVCName,
              },
            },
          ],
        },
      },
    },
  },
}
