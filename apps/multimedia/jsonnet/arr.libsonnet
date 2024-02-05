local defaults = {
  local defaults = self,
  name: error 'must provide name',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  port: error 'must provide port',
  exporter: {
    image: 'ghcr.io/onedr0p/exportarr:v1.6.0',
    port: 9708,
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
  multimediaPVCName: '',
  downloadsPVCName: '',
};

function(params) {
  local j = self,
  _config:: defaults + params {
    exporter: if std.objectHas(params, 'exporter') then defaults.exporter + params.exporter else defaults.exporter,
  },

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
          protocol: 'TCP',
        },
        {
          name: $.statefulset.spec.template.spec.containers[1].ports[0].name,
          targetPort: $.statefulset.spec.template.spec.containers[1].ports[0].name,
          port: $.statefulset.spec.template.spec.containers[1].ports[0].containerPort,
          protocol: 'TCP',
        },
      ],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
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

  prometheusRule: std.prune({
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata,
    spec: {
      groups: [{
        name: 'exportarr',
        rules: [{
          alert: 'ExportarrDown',
          annotations: {
            summary: 'Exportarr is down',
            description: |||
              Exportarr responsible for data collection from %s is down. Check configuration and logs.
            ||| % ([$._config.name]),
          },
          expr: 'up{job="%s"} == 0' % ([$.serviceMonitor.metadata.name]),
          'for': '5m',
          labels: {
            severity: 'critical',
          },
        }],
      }, {
        name: '%s' % ([$._config.name]),
        rules: [{
          alert: '%sDown' % ([$._config.name]),
          annotations: {
            summary: '%s is Down' % ([$._config.name]),
            description: |||
              Arr Application %s in namespace {{ $labels.namespace }} is not reporting status check correctly.
            ||| % ([$._config.name]),
          },
          expr: '%s_system_status{job="%s"} != 1' % ([$._config.name, $.serviceMonitor.metadata.name]),
          'for': '15m',
          labels: {
            severity: 'critical',
          },
        }, {
          alert: '%sUnhealthy' % ([$._config.name]),
          annotations: {
            summary: '%s is unhealthy' % ([$._config.name]),
            description: |||
              Arr Application %s is having issues with {{ $labels.source }} health check - {{ $labels.message }}.
              For more infromation check {{ $labels.wikiurl }}.
            ||| % ([$._config.name]),
          },
          expr: 'max_over_time(%s_system_health_issues{job="%s",source!="UpdateCheck",source!="IndexerLongTermStatusCheck"}[1h]) == 1' % ([$._config.name, $.serviceMonitor.metadata.name]),
          'for': '2h',
          labels: {
            severity: 'warning',
          },
        }] + [if params.name == 'prowlarr' then {
          alert: 'ProwlarIndexerUnhealthy',
          annotations: {
            summary: 'One of Prowlarr Indexers stopped working properly',
            description: |||
              Prowalarr reports problems with indexer - {{ $labels.message }}.
              For more infromation check {{ $labels.wikiurl }}.
            |||,
          },
          expr: 'max_over_time(%s_system_health_issues{job="%s",source="IndexerLongTermStatusCheck"}[1h]) == 1' % ([$._config.name, $.serviceMonitor.metadata.name]),
          'for': '2h',
          labels: {
            severity: 'warning',
          },
        }],
      }],
    },
  }),

  [if std.objectHas(params, 'storage') && std.objectHas(params.storage, 'backups') && std.objectHas(params.storage.backups, 'pvcSpec') && std.length(params.storage.backups.pvcSpec) > 0 then 'backupsPVC']: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: $._metadata {
      //name: 'backups',
      name: $._metadata.name + '-config-backup',
    },
    spec: $._config.storage.backups.pvcSpec,
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
      local multimediaPVCmount = if std.objectHas(params, 'multimediaPVCName') && std.length(params.multimediaPVCName) > 0 then [{
        mountPath: '/multimedia',
        name: 'multimedia',
      }] else [],
      local downloadsPVCmount = if std.objectHas(params, 'downloadsPVCName') && std.length(params.downloadsPVCName) > 0 then [{
        mountPath: '/download/completed',
        name: 'downloads',
      }] else [],
      volumeMounts: [
        {
          mountPath: '/config',
          name: 'config',
        },
        {
          mountPath: '/backup',
          name: 'backup',
        },
      ] + multimediaPVCmount + downloadsPVCmount,
      resources: $._config.resources,
    },

    local e = {
      args: [$._config.name],
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
          value: std.toString($._config.exporter.port),
        },
      ],
      image: $._config.exporter.image,
      name: 'exportarr',
      ports: [{
        containerPort: $._config.exporter.port,
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

    /*local init = {
      command: ['/bin/sh'],
      args: ['-c', "cd /config && unzip $(find /backup -type f -exec stat -c '%Y :%y %n' {} + | sort -nr | head -n1 | cut -d' ' -f4) && chown 1000:1000 /config/*"],
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
    },*/

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
          //[if std.objectHas(params, 'storage') && std.objectHas(params.storage, 'backups') && std.objectHas(params.storage.backups, 'pvcSpec') && std.length(params.storage.backups.pvcSpec) > 0 then 'initContainers']: [init],
          containers: [c, e],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          local multimediaVolume = if std.objectHas(params, 'multimediaPVCName') && std.length(params.multimediaPVCName) > 0 then [{
            name: 'multimedia',
            persistentVolumeClaim: {
              claimName: $._config.multimediaPVCName,
            },
          }] else [],
          local downloadsVolume = if std.objectHas(params, 'downloadsPVCName') && std.length(params.downloadsPVCName) > 0 then [{
            name: 'downloads',
            persistentVolumeClaim: {
              claimName: $._config.downloadsPVCName,
            },
          }] else [],
          local backupVolume = if std.objectHas(params, 'storage') && std.objectHas(params.storage, 'backups') && std.objectHas(params.storage.backups, 'pvcSpec') && std.length(params.storage.backups.pvcSpec) > 0 then [{
            name: 'backup',
            persistentVolumeClaim: {
              claimName: $.backupsPVC.metadata.name,
            },
          }] else [{
            name: 'backup',
            emptyDir: {},
          }],
          volumes: multimediaVolume + downloadsVolume + backupVolume,
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
