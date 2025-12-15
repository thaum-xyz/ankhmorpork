local defaults = {
  local defaults = self,
  name: error 'must provide name',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  port: error 'must provide port',
  exporter: {
    image: 'ghcr.io/onedr0p/exportarr:v2.0.1',
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
  domain: '',
  ingressClassName: 'private',
  database: {
    usernameRef: {
      key: 'username',
      name: 'postgres-%s-user' % defaults.name,
    },
    passwordRef: {
      key: 'password',
      name: 'postgres-%s-user' % defaults.name,
    },
    host: 'postgres-%s-rw' % defaults.name,
    port: 5432,
    mainDB: defaults.name,
    logDB: 'logs',
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

  ingress: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata,
    spec: {
      ingressClassName: $._config.ingressClassName,
      rules: [{
        host: $._config.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: $._config.name,
                port: {
                  number: $.service.spec.ports[0].port,
                },
              },
            },
          }],
        },
      }],
      tls: [{
        hosts: [$._config.domain],
        secretName: '%s-tls' % std.strReplace($._config.domain, '.', '-'),
      }],
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: [{
        port: $.statefulset.spec.template.spec.containers[1].ports[0].name,
        scrapeTimeout: '30s',
        interval: '100s',
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
        mountPath: '/download',
        name: 'downloads',
      }] else [],
      volumeMounts: [
        {
          mountPath: '/config',
          name: 'config',
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

    local dbInit = {
      env: [
        {
          name: 'POSTGRES_USER',
          valueFrom: {
            secretKeyRef: $._config.database.usernameRef,
          },
        },
        {
          name: 'POSTGRES_PASS',
          valueFrom: {
            secretKeyRef: $._config.database.passwordRef,
          },
        },
        {
          name: 'POSTGRES_HOST',
          value: $._config.database.host,
        },
        {
          name: 'POSTGRES_PORT',
          value: std.toString($._config.database.port),
        },
        {
          name: 'POSTGRES_MAIN_DB',
          value: $._config.database.mainDB,
        },
        {
          name: 'POSTGRES_LOG_DB',
          value: $._config.database.logDB,
        },
      ],
      image: 'mikefarah/yq:4.49.2',
      name: 'postgres-setup',
      command: ['sh', '-c'],
      args: [
        |||
          set -euo pipefail
          mkdir -p /config/backups
          if [ -f /config/config.xml ]; then
            cp /config/config.xml /config/backups/config.xml.$(date +%Y%m%d%H%M%S).bak
          else
            touch /config/config.xml
          fi
          export POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_PASS POSTGRES_MAIN_DB POSTGRES_LOG_DB
          yq -i '
                  (.Config.PostgresHost = env(POSTGRES_HOST)) |
                  (.Config.PostgresPort = env(POSTGRES_PORT)) |
                  (.Config.PostgresUser = env(POSTGRES_USER)) |
                  (.Config.PostgresPassword = env(POSTGRES_PASS)) |
                  (.Config.PostgresMainDb = env(POSTGRES_MAIN_DB)) |
                  (.Config.PostgresLogDb = env(POSTGRES_LOG_DB))
                ' /config/config.xml
        |||,
      ],
      volumeMounts: [{
        mountPath: '/config',
        name: 'config',
      }],
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
          initContainers: [dbInit],
          containers: [c, e],
          restartPolicy: 'Always',
          securityContext: {
            fsGroup: 1000,
          },
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
          volumes: multimediaVolume + downloadsVolume,
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
