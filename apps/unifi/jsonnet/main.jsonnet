local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
};

local all = {
  poller: {
    _metadata:: {
      name: 'poller',
      namespace: config.namespace,
      labels: {
        'app.kubernetes.io/name': 'unifi-poller',
        'app.kubernetes.io/component': 'exporter',
      },
    },
    configuration: sealedsecret($.poller._metadata, config.poller.credentials) + {
      spec+: {
        metadata+: $.poller._metadata,
        template+: {
          data: {
            'unifi-poller.conf': config.poller.config,
          },
        },
      },
    },
    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: $.poller._metadata,
    },

    local c = {
      image: config.poller.image,
      name: 'unifi-poller',
      ports: [{
        containerPort: 9130,
        name: 'metrics',
        protocol: 'TCP',
      }],
      resources: config.poller.resources,
      volumeMounts: [{
        mountPath: '/config/unifi-poller.conf',
        name: 'config',
        subPath: 'unifi-poller.conf',
      }],
    },
    deployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: $.poller._metadata,
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app.kubernetes.io/component': 'exporter',
            'app.kubernetes.io/name': 'unifi-poller',
          },
        },
        template: {
          metadata: $.poller._metadata {
            annotations: {
              'checksum.config/md5': std.md5(std.toString(config.poller.credentials)),
            },
          },
          spec: {
            containers: [c],
            restartPolicy: 'Always',
            volumes: [{
              name: 'config',
              secret: {
                secretName: $.poller.configuration.metadata.name,
              },
            }],
          },
        },
      },
    },
    podMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PodMonitor',
      metadata: $.poller._metadata,
      spec: {
        podMetricsEndpoints: [{
          interval: '30s',
          port: 'metrics',
        }],
        selector: {
          matchLabels: {
            'app.kubernetes.io/component': 'exporter',
            'app.kubernetes.io/name': 'unifi-poller',
          },
        },
      },
    },
  },
  backup:: {
    _metadata:: {
      name: 'backup',
      namespace: config.namespace,
      labels: {
        'app.kubernetes.io/name': 'backup',
      },
    },
    sshprivkey: sealedsecret(
      $.backup._metadata { name: 'sshprivkey' },
      { id_rsa: config.backup.encryptedSSHKey }
    ),

    local c = {
      name: 'copier',
      image: config.backup.image,
      command: [
        'rsync',
        '-av',
        '--delete',
        '-e',
        'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null',
        'root@' + config.backup.host + ':/data/autobackup/',
        '/backup/',
      ],
      resources: {
        requests: {
          cpu: '520m',
          memory: '20Mi',
        },
        limits: {
          cpu: '800m',
          memory: '100Mi',
        },
      },
      volumeMounts: [
        {
          name: 'backups',
          mountPath: '/backups',
        },
        {
          name: 'ssh',
          mountPath: '/root/.ssh',
          readOnly: true,
        },
      ],
    },
    cronjob: {
      apiVersion: 'batch/v1',
      kind: 'CronJob',
      metadata: $.backup._metadata,
      spec: {
        successfulJobsHistoryLimit: 1,
        failedJobsHistoryLimit: 3,
        concurrencyPolicy: 'Forbid',
        schedule: '6 6 * * sun',  // At 06:06 on Sunday
        jobTemplate: {
          spec: {
            template: {
              spec: {
                containers: [c],
                volumes: [
                  {
                    name: 'backups',
                    persistentVolumeClaim: { claimName: $.backup.pvc.metadata.name },
                  },
                  {
                    name: 'ssh',
                    secret: {
                      secretName: $.backup.sshprivkey.metadata.name,
                      defaultMode: 384,  // Same as 0600
                    },
                  },
                ],
                restartPolicy: 'OnFailure',
              },
            },
          },
        },
      },
    },
    pvc: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: $.backup._metadata,
      spec: {
        storageClassName: 'managed-nfs-storage',
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '100Mi',
          },
        },
      },
    },
  },
  restarter: {
    _metadata:: {
      name: 'restarter',
      namespace: config.namespace,
      labels: {},
    },

    prometheusRule: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PrometheusRule',
      metadata: $.restarter._metadata,
      spec: {
        groups: [{
          name: 'unifi-restarter',
          rules: [
            {
              alert: 'NodeDown',
              expr: 'count by (node) (up{job="node-exporter"} == 0) > 0 AND count by (node) (up{job="kubelet", metrics_path="/metrics"} == 0) > 0',
              "for": "15m",
              annotations: {
                description: 'Metrics from node_exporter and kubelet cannot be gathered for node {{ $labels.node }} suggesting node is down. Alert should be automatically remediated by attempting node power cycle',
                summary: 'Node is down for extended period of time',
              },
              labels: {
                severity: 'warning', //TODO: change to `info` when automated restarter is finished and deployed
              },
            },
          ],
        }],
      },
    },
  },
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
