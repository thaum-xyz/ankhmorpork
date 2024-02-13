local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;

local defaults = {
  local defaults = self,
  name: error 'must provide name',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  port: error 'must provide port',
  loadBalancerIP: '',
  runtimeClassName: '',
  hostname: '',
  exporter: {
    image: 'quay.io/paulfantom/plex_exporter:1.0.0',
    port: 9594,
    config: {
      secretName: '',
    },
    resources: {
      limits: {
        memory: '20Mi',
      },
      requests: {
        memory: '11Mi',
      },
    },
  },
  affinity: {},
  resources: {
    requests: {
      cpu: '500m',
      memory: '3Gi',
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
  plexClaim: {
    secretName: '',
  },
  storage: {
    library: {
      pvcSpec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '5Gi',
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
  moviesPVCName: '',
  tvshowsPVCName: '',
};


function(params) {
  //_config:: std.mergePatch(defaults, params),
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
      externalTrafficPolicy: 'Local',
      loadBalancerIP: $._config.loadBalancerIP,
      type: 'LoadBalancer',
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
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: [{
        port: $.statefulset.spec.template.spec.containers[1].ports[0].name,
        interval: '120s',
      }],
      selector: {
        matchLabels: $._config.selectorLabels,
      },
    },
  },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: $._metadata,
    spec: {
      groups: [{
        name: 'plex.rules',
        rules: [{
          alert: 'PlexDown',
          annotations: {
            description: 'Data from plex server cannot be retreived and server is not ready',
            runbook_url: 'https://runbooks.thaum.xyz/runbooks/thaum-xyz/plexdown',
            summary: 'Plex Server is down',
          },
          // TODO: parametrize!!!
          expr: |||
            absent(plex_server_info{namespace="multimedia"}) == 1
            AND
            kube_pod_container_status_ready{namespace="multimedia",container="plex"} != 1
          |||,
          'for': '20m',
          labels: {
            severity: 'critical',
          },
        }, {
          alert: 'PlexExporterNoData',
          annotations: {
            description: 'Plex exporter cannot get data from plex server.',
            runbook_url: 'https://runbooks.thaum.xyz/runbooks/thaum-xyz/plexexporternodata',
            summary: 'Plex Server is down',
          },
          expr: 'absent(plex_sessions_active_count) == 1',
          'for': '14m',
          labels: {
            severity: 'warning',
          },
        }, {
          alert: 'PlexNoMediaLibraries',
          annotations: {
            description: 'Plex is not reporting any content in a library',
            runbook_url: 'https://runbooks.thaum.xyz/runbooks/thaum-xyz/plexnomedialibraries',
            summary: 'Plex is not reporting any content in one of libraries',
          },
          expr: |||
            (plex_media_server_library_media_count < 1)
            OR
            absent(plex_media_server_library_media_count)
          |||,
          'for': '30m',
          labels: {
            severity: 'warning',
          },
        }],
      }],
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

  local p = {
    env: [
      { name: 'TZ', value: 'Europe/Berlin' },
      { name: 'PUID', value: '1000' },
      { name: 'GUID', value: '1000' },
      { name: 'NVIDIA_DRIVER_CAPABILITIES', value: 'all' },
      { name: 'ALLOWED_NETWORKS', value: '192.168.2.0/24,10.42.0.0/16' },  // FIXME: parametrize!!!
      { name: 'ADVERTISE_IP', value: 'http://192.168.2.98:32400/' },  // FIXME: parametrize!!!
    ],
    envFrom: [{
      secretRef: {
        name: $._config.plexClaim.secretName,
      },
    }],
    image: $._config.image,
    name: 'plex',
    ports: [{
      containerPort: $._config.port,
      name: 'plex',
      protocol: 'TCP',
    }],
    readinessProbe: {
      failureThreshold: 3,
      httpGet: {
        path: '/identity',
        port: $._config.port,
        scheme: 'HTTP',
      },
      initialDelaySeconds: 30,
      periodSeconds: 10,
      successThreshold: 1,
      timeoutSeconds: 5,
    },
    resources: $._config.resources,
    volumeMounts: [
      {
        mountPath: '/config',
        name: 'library',
      },
      {
        mountPath: '/transcode',
        name: 'transcode',
      },
      {
        mountPath: '/backup',
        name: 'backup',
      },
      {
        mountPath: '/data/movies',
        name: 'movies',
      },
      {
        mountPath: '/data/tv',
        name: 'tv',
      },
    ],
  },

  local e = {
    args: [
      '--config=/config.json',
    ],
    image: $._config.exporter.image,
    name: 'exporter',
    ports: [{
      containerPort: $._config.exporter.port,
      name: 'metrics',
      protocol: 'TCP',
    }],
    resources: $._config.exporter.resources,
    volumeMounts: [{
      mountPath: '/config.json',
      name: 'exporter-config',
      readOnly: true,
      subPath: 'config.json',
    }],
  },

  statefulset: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      selector: {
        matchLabels: $._config.selectorLabels,
      },
      serviceName: $._metadata.name,
      template: {
        metadata: {
          annotations: {
            'kubectl.kubernetes.io/default-container': 'plex',
          },
          labels: $._config.selectorLabels,
        },
        spec:
          if $._config.runtimeClassName != '' then {
            runtimeClassName: $._config.runtimeClassName,
          } else {} + {
            affinity: $._config.affinity,
            serviceAccountName: $.serviceAccount.metadata.name,
            containers: [p, e],
            hostname: $._config.hostname,
            nodeSelector: {
              'kubernetes.io/arch': 'amd64',
              'kubernetes.io/os': 'linux',
            },
            volumes: [
              {
                emptyDir: {},
                name: 'transcode',
              },
              {
                name: 'backup',
                persistentVolumeClaim: {
                  claimName: $._metadata.name + '-backup',
                },
              },
              {
                name: 'exporter-config',
                secret: {
                  optional: true,
                  secretName: $._config.exporter.config.secretName,
                },
              },
              {
                name: 'movies',
                persistentVolumeClaim: {
                  claimName: $._config.moviesPVCName,
                },
              },
              {
                name: 'tv',
                persistentVolumeClaim: {
                  claimName: $._config.tvshowsPVCName,
                },
              },
            ],
          },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: 'library',
        },
        spec: $._config.storage.library.pvcSpec,
      }],
    },
  },
}
