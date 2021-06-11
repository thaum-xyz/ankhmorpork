local sealedsecret = (import '../../../lib/sealedsecret.libsonnet').sealedsecret;

local configYAML = (importstr './settings.yaml');

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
  backup: {
    _metadata:: {
      name: 'backup',
      namespace: config.namespace,
    },
    sshprivkey: sealedsecret(
      {
        name: 'sshprivkey',
        namespace: config.namespace,
      },
      { id_rsa: config.backup.encryptedSSHKey }
    ),
    cronjob: {
      apiVersion: 'batch/v1beta1',
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
                containers: [{
                  name: 'copier',
                  image: 'quay.io/paulfantom/rsync',
                  command: [
                    'rsync',
                    '-av',
                    '--delete',
                    '-e',
                    'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null',
                    'root@' + config.backup.host + ':/data/autobackup/',
                    '/backup/',
                  ],
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
                }],
                volumes: [
                  {
                    name: 'backups',
                    persistentVolumeClaim: { claimName: $.backup.pvc.metadata.name },
                  },
                  {
                    name: 'ssh',
                    secret: {
                      secretName: $.backup.sshprivkey.metadata.name,
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
};

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
