// TODO list:

// k3s additions:
// - kube-controller-manager-prometheus-discovery service
// - kube-scheduler-prometheus-discovery

// Things to fix in kube-prometheus
// - prometheus-pvc should be an addon
// - better `examples/` directory schema
// - addon to add 'runbook_url' annotation to every alert
// - fix SM label selector for coreDNS in kube-prometheus
// - ...

// TODO list for later
// - loading dashboards
//     from mixins:
//       - kubernetes-mixin
//       - prometheus
//       - node-exporter
//       - coredns
//       - sealed-secrets
//       - go runtime metrics (https://github.com/grafana/jsonnet-libs/tree/master/go-runtime-mixin)
//     from json:
//       - blackbox-exporter
//       - smokeping
//       - unifi
//       - nginx-controller
//       - mysql (x2)
//       - redis
//       - home dashboard

local addArgs(args, name, containers) = std.map(
  function(c) if c.name == name then
    c {
      args+: args,
    }
  else c,
  containers,
);

local probe(name, namespace, labels, module, targets) = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'Probe',
  metadata: {
    name: name,
    namespace: namespace,
    labels: labels,
  },
  spec: {
    prober: {
      // TODO: point to https version at 9115
      url: 'blackbox-exporter.monitoring.svc:19115',
    },
    module: module,
    targets: targets,
  },
};

// TODO: propose to https://github.com/slok/sloth
local sloth = (import 'github.com/thaum-xyz/jsonnet-libs/apps/sloth/sloth.libsonnet');
local exporter = (import 'github.com/thaum-xyz/jsonnet-libs/apps/prometheus-exporter/exporter.libsonnet');
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;
local antiaffinity = (import 'github.com/thaum-xyz/jsonnet-libs/utils/podantiaffinity.libsonnet');
local pagespeed = (import 'github.com/thaum-xyz/jsonnet-libs/apps/pagespeed/pagespeed.libsonnet');
local snmp = (import 'github.com/thaum-xyz/jsonnet-libs/apps/snmp-exporter/snmp-exporter.libsonnet');
local kubeEventsExporter = (import 'github.com/thaum-xyz/jsonnet-libs/apps/kube-events-exporter/kube-events-exporter.libsonnet');
local pushgateway = (import 'github.com/thaum-xyz/jsonnet-libs/apps/pushgateway/pushgateway.libsonnet');

local mixin = (import 'kube-prometheus/lib/mixin.libsonnet');

local ingressAnnotations = {
  'kubernetes.io/ingress.class': 'nginx',
  'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
  'nginx.ingress.kubernetes.io/auth-url': 'https://auth.ankhmorpork.thaum.xyz/oauth2/auth',
  'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.ankhmorpork.thaum.xyz/oauth2/start?rd=$scheme://$host$escaped_request_uri',
};

local kp =
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/main.libsonnet') +
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/addons/all-namespaces.libsonnet') +
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/addons/windows.libsonnet') +
  // (import 'lib/ingress.libsonnet') +
  // (import 'lib/additional-scrape-configs.libsonnet') +
  // (import './lib/k3s.libsonnet') +
  // (import './config.json') +
  {
    //
    // Configuration
    //

    // TODO: figure out how to make this a JSON/YAML file!
    values+:: (import '../config.jsonnet'),

    //
    // Objects customization
    // kube-prometheus objects first
    //
    prometheusOperator+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              containers: addArgs(['--log-level=debug'], 'prometheus-operator', super.containers),
            },
          },
        },
      },
    },

    alertmanager+: {
      // alertmanager secret is stored as ConfigMapSecret in plain yaml file
      secret:: null,
      // TODO: move ingress and externalURL to an addon in kube-prometheus
      alertmanager+: {
        spec+: {
          externalUrl: 'https://alertmanager.' + $.values.common.baseDomain,
        },
      },
      serviceAccount+: {
        automountServiceAccountToken: false,  // TODO: move into kube-prometheus
      },
      ingress: {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
          name: 'alertmanager',
          namespace: $.alertmanager.alertmanager.metadata.namespace,
          annotations: ingressAnnotations {
            'nginx.ingress.kubernetes.io/affinity': 'cookie',
            'nginx.ingress.kubernetes.io/affinity-mode': 'persistent',
            'nginx.ingress.kubernetes.io/session-cookie-hash': 'sha1',
            'nginx.ingress.kubernetes.io/session-cookie-name': 'routing-cookie',
          },
        },
        spec: {
          tls: [{
            hosts: ['alertmanager.ankhmorpork.thaum.xyz'],
            secretName: 'alertmanager-tls',
          }],
          rules: [{
            host: 'alertmanager.ankhmorpork.thaum.xyz',
            http: {
              paths: [{
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: 'alertmanager-main',
                    port: {
                      name: 'web',
                    },
                  },
                },
              }],
            },
          }],
        },
      },
    },

    blackboxExporter+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              affinity: antiaffinity.podantiaffinity('blackbox-exporter'),
            },
          },
        },
      },
      promDemoProbe: probe('prometheus-demo', $.blackboxExporter.deployment.metadata.namespace, $.blackboxExporter._config.commonLabels, 'http_2xx', $.values.blackboxExporter.probes.promDemo),
      thaumProbe: probe('thaum-sites', $.blackboxExporter.deployment.metadata.namespace, $.blackboxExporter._config.commonLabels, 'http_2xx', $.values.blackboxExporter.probes.thaumSites),
      ingressProbe: probe('ankhmorpork', $.blackboxExporter.deployment.metadata.namespace, $.blackboxExporter._config.commonLabels, 'http_2xx', $.values.blackboxExporter.probes.ingress),
    },

    nodeExporter+: {
      // node_exporter is deployed separately via Ansible
      // TODO: Move node_exporter into k3s installation
      clusterRole:: null,
      clusterRoleBinding:: null,
      daemonset:: null,
      service:: null,
      serviceAccount:: null,
      serviceMonitor:: null,
    },

    // Using metrics-server instead of prometheus-adapter
    prometheusAdapter:: null,

    // FIXME(paulfantom): Figure out what is hiding `prometheus` top-level object so remapping won't be necessary
    prometheusk8s: $.prometheus {
      prometheus+: {
        spec+: {
          // TODO: move ingress and externalURL to an addon
          externalUrl: 'https://prometheus.' + $.values.common.baseDomain,
          retention: '7d',
          nodeSelector+: {
            'storage.infra/local': 'true',
          },
          // FIXME: reenable
          securityContext:: null,
          queryLogFile: '/prometheus/query.log',

          storage: {
            volumeClaimTemplate: {
              metadata: {
                name: 'promdata',
              },
              spec: {
                storageClassName: 'local-path',  // For performance reasons use local disk
                accessModes: ['ReadWriteOnce'],
                resources: {
                  requests: { storage: '40Gi' },
                },
              },
            },
          },
        },
      },

      ingress: {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
          name: 'prometheus',
          namespace: $.prometheus.prometheus.metadata.namespace,
          annotations: ingressAnnotations,
        },
        spec: {
          tls: [{
            hosts: ['prometheus.ankhmorpork.thaum.xyz'],
            secretName: 'prometheus-tls',
          }],
          rules: [{
            host: 'prometheus.ankhmorpork.thaum.xyz',
            http: {
              paths: [{
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: 'prometheus-k8s',
                    port: {
                      name: 'web',
                    },
                  },
                },
              }],
            },
          }],
        },
      },
    },

    kubeStateMetrics+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              containers:
                addArgs(['--metric-labels-allowlist=nodes=[kubernetes.io/arch,gpu.infra/intel,network.infra/type]'], 'kube-state-metrics', super.containers),
            },
          },
        },
      },
    },

    kubernetesControlPlane+: {
      // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
      serviceMonitorApiserver:: null,
      serviceMonitorKubeControllerManager:: null,
      serviceMonitorKubeScheduler:: null,
      serviceMonitorKubelet+: {
        spec+: {
          endpoints+: [
            // Scrape new /metrics/resource kubelet endpoint. TODO: move to kube-prometheus
            {
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              honorLabels: true,
              interval: '30s',
              path: '/metrics/resource',
              port: 'https-metrics',
              relabelings: [{
                sourceLabels: ['__metrics_path__'],
                targetLabel: 'metrics_path',
              }],
              scheme: 'https',
              tlsConfig: {
                insecureSkipVerify: true,
              },
            },
            // This allows scraping external node-exporter endpoints
            // TODO: Remove after moving node-exporter into a cluster
            {
              interval: '30s',
              port: 'https-metrics',
              relabelings: [
                {
                  action: 'replace',
                  regex: '(.+)(?::\\d+)',
                  replacement: '$1:9100',
                  sourceLabels: ['__address__'],
                  targetLabel: '__address__',
                },
                {
                  action: 'replace',
                  replacement: 'node-exporter',
                  sourceLabels: ['endpoint'],
                  targetLabel: 'endpoint',
                },
                {
                  action: 'replace',
                  replacement: 'node-exporter',
                  targetLabel: 'job',
                },
              ],
            },
          ],
        },
      },
    },

    kubePrometheus+: {
      // Exclude job="windows" from TargetDown alert
      prometheusRule+: {
        spec+: {
          groups: std.map(function(ruleGroup) ruleGroup {
            rules: std.map(
              function(rule) if 'alert' in rule && rule.alert == 'TargetDown' then
                rule { expr: '100 * (count(up{job!="windows",instance!="biuro:9100"} == 0) BY (job, namespace, service) / count(up{job!="windows",instance!="biuro:9100"}) BY (job, namespace, service)) > 10' }
              else rule,
              ruleGroup.rules,
            ),
          }, super.groups),
        },
      },
    },

    grafana+: {
      service+: {
        spec+: {
          type: 'ClusterIP',
        },
      },
      config+:: {},
      dashboardSources+:: {},
      dashboardDefinitions+:: {},
      deployment+: {
        spec+: {
          template+: {
            metadata+: {
              // Unwanted when using persistance
              annotations:: {},
            },
            spec+: {
              containers: std.map(
                function(c)
                  if c.name == 'grafana' then
                    c {
                      volumeMounts: [
                        {
                          mountPath: '/var/lib/grafana',
                          name: 'grafana-storage',
                        },
                        {
                          mountPath: '/etc/grafana/provisioning/datasources',
                          name: 'grafana-datasources',
                        },
                      ],
                    }
                  else c,
                super.containers,
              ),
              // TODO: figure out why this was needed. Longhorn issues?
              securityContext: {
                runAsNonRoot: true,
                runAsUser: 472,
              },
              // Enable storage persistence
              volumes: [
                {
                  name: 'grafana-storage',
                  persistentVolumeClaim: {
                    claimName: 'grafana-data',
                  },
                },
                {
                  name: 'grafana-datasources',
                  secret: {
                    secretName: 'grafana-datasources',
                  },
                },
              ],
            },
          },
        },
      },

      pvc: {
        kind: 'PersistentVolumeClaim',
        apiVersion: 'v1',
        metadata: {
          name: 'grafana-data',
          namespace: 'monitoring',
        },
        spec: {
          storageClassName: 'managed-nfs-storage',
          accessModes: ['ReadWriteMany'],
          resources: {
            requests: {
              storage: '60Mi',
            },
          },
        },
      },

      ingress: {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
          name: 'grafana',
          namespace: 'monitoring',
          annotations: {
            'kubernetes.io/ingress.class': 'nginx',
            'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
            'nginx.ingress.kubernetes.io/auth-url': 'https://auth.ankhmorpork.thaum.xyz/oauth2/auth',
            'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.ankhmorpork.thaum.xyz/oauth2/start?rd=$scheme://$host$escaped_request_uri',
            'nginx.ingress.kubernetes.io/auth-response-headers': 'X-Auth-Request-Email',
          },
        },
        spec: {
          tls: [{
            hosts: ['grafana.ankhmorpork.thaum.xyz'],
            secretName: 'grafana-tls',
          }],
          rules: [{
            host: 'grafana.ankhmorpork.thaum.xyz',
            http: {
              paths: [{
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: 'grafana',
                    port: { name: 'http' },
                  },
                },
              }],
            },
          }],
        },
      },

    },

    //
    // Custom components
    //

    kubeEventsExporter: kubeEventsExporter($.values.kubeEventsExporter),
    pushgateway: pushgateway($.values.pushgateway),
    // TODO: Add pagespeed API key to workaround rate limits
    pagespeed: pagespeed($.values.pagespeed) + {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              nodeSelector+: {
                'kubernetes.io/os': 'linux',
                'kubernetes.io/arch': 'amd64',
              },
            },
          },
        },
      },
    },
    smokeping: exporter($.values.smokeping) + {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              affinity: antiaffinity.podantiaffinity('smokeping'),
              containers: std.map(function(c) c {
                securityContext: { capabilities: { add: ['NET_RAW'] } },
              }, super.containers),
            },
          },
        },
      },
    },
    // Consider moving to a separate lib dedicated to json_exporter
    uptimerobot: exporter($.values.uptimerobot) + {
      deployment+: {
        spec+: {
          template+: {
            metadata+: {
              annotations+: {
                'checksum.config/md5': std.md5($.values.uptimerobot.config),
              },
            },
            spec+: {
              containers: std.map(function(c) c {
                volumeMounts: [{
                  mountPath: '/etc/json_exporter/',
                  name: 'uptimerobot',
                  readOnly: true,
                }],
              }, super.containers),
              volumes: [{
                name: 'uptimerobot',
                secret: {
                  secretName: $.uptimerobot.configuration.spec.template.metadata.name,
                },
              }],
            },
          },
        },
      },
      service: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: $.uptimerobot.deployment.metadata,
        spec: {
          ports: [{
            name: $.uptimerobot.deployment.spec.template.spec.containers[0].ports[0].name,
            port: $.uptimerobot.deployment.spec.template.spec.containers[0].ports[0].containerPort,
            targetPort: $.uptimerobot.deployment.spec.template.spec.containers[0].ports[0].name,
          }],
          selector: $.uptimerobot.podMonitor.spec.selector.matchLabels,
        },
      },
      // Using ServiceMonitor just to note that Service is necessary and to fail when it disappears
      podMonitor+:: {},
      serviceMonitor: {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: $.uptimerobot.deployment.metadata,
        spec: {
          endpoints: $.uptimerobot.podMonitor.spec.podMetricsEndpoints,
          selector: $.uptimerobot.podMonitor.spec.selector,
        },
      },
      configuration: sealedsecret($.uptimerobot.deployment.metadata, $.values.uptimerobot.credentials) + {
        spec+: {
          template+: {
            data: {
              'config.yml': $.values.uptimerobot.config,
            },
          },
        },
      },
      probe: {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'Probe',
        metadata: $.uptimerobot.deployment.metadata,
        spec: {
          interval: '150s',
          prober: {
            url: $.uptimerobot.service.metadata.name + '.' + $.uptimerobot.service.metadata.namespace + '.svc:7979',
          },
          targets: {
            staticConfig: {
              static: ['https://api.uptimerobot.com/v2/getMonitors'],
            },
          },
          metricRelabelings: [
            {
              sourceLabels: ['url'],
              targetLabel: 'instance',
            },
            {
              sourceLabels: ['url'],
              targetLabel: 'instance',
              regex: '(https://[a-zA-Z0-9.-]+).*',
              replacement: '$1/',
            },
          ],
        },
      },
    },

    sloth: sloth($.values.sloth),

    other: {
      local thaumMixin = import 'mixin/mixin.libsonnet',
      thaumPrometheusRule: mixin({
        name: 'thaum-rules',
        namespace: 'monitoring',
        labels: {
          prometheus: 'k8s',
          role: 'alert-rules',
        },
        mixin: thaumMixin,
      }).prometheusRules,
    },

    // TODO: Move receiver part into separate addon and donate to kube-prometheus
    receiver: {
      // Move to a loop
      serviceWrite0: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: $.prometheus.service.metadata { name: 'prometheus-k8s-write-0' },
        spec: {
          ports: $.prometheus.service.spec.ports,
          selector: $.prometheus.service.spec.selector { 'statefulset.kubernetes.io/pod-name': 'prometheus-k8s-0' },
        },
      },
      serviceWrite1: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: $.prometheus.service.metadata { name: 'prometheus-k8s-write-1' },
        spec: {
          ports: $.prometheus.service.spec.ports,
          selector: $.prometheus.service.spec.selector { 'statefulset.kubernetes.io/pod-name': 'prometheus-k8s-1' },
        },
      },
      ingress: {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
          name: 'prometheus-remote-write',
          namespace: $.prometheus.prometheus.metadata.namespace,
          annotations: {
            'kubernetes.io/ingress.class': 'nginx',
            'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
            'nginx.ingress.kubernetes.io/auth-type': 'basic',
            'nginx.ingress.kubernetes.io/auth-secret': 'prometheus-remote-write-auth',
            'nginx.ingress.kubernetes.io/rewrite-target': '/$2',
          },
        },
        spec: {
          tls: [{
            hosts: ['push.ankhmorpork.thaum.xyz'],
            secretName: 'prometheus-remote-write-tls',
          }],
          rules: [{
            host: 'push.ankhmorpork.thaum.xyz',
            http: {
              paths: [
                {
                  path: '/primary(/|$)(.*)',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'prometheus-k8s-write-0',
                      port: {
                        name: 'web',
                      },
                    },
                  },
                },
                {
                  path: '/secondary(/|$)(.*)',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'prometheus-k8s-write-1',
                      port: {
                        name: 'web',
                      },
                    },
                  },
                },
              ],
            },
          }],
        },
      },
      remoteWriteAuth: sealedsecret(
        {
          name: 'prometheus-remote-write-auth',
          namespace: $.prometheus.prometheus.metadata.namespace,
        },
        {
          auth: $.values.prometheus.remoteWriteAuth,
        },
      ),
    },

  } +
  // kube-linter annotations need to be added after all objects are created
  (import 'lib/kube-linter.libsonnet');

//
// Manifestation
//

{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(kp[component][resource])
  for component in std.objectFields(kp)
  for resource in std.objectFields(kp[component])
}
