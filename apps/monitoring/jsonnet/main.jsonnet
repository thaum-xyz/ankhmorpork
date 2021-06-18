// TODO list:

// k3s additions:
// - kube-controller-manager-prometheus-discovery service
// - kube-scheduler-prometheus-discovery

// Things to fix in kube-prometheus
// - addon/example for additionalScrapeConfigs?
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
//       - argocd
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
// TODO: consider moving this to some other place (maybe jsonnet-libs repo?)
local exporter = (import 'lib/exporter.libsonnet');
local sealedsecret = (import 'github.com/thaum-xyz/jsonnet-libs/utils/sealedsecret.libsonnet').sealedsecret;
local antiaffinity = (import 'github.com/thaum-xyz/jsonnet-libs/utils/podantiaffinity.libsonnet');
local pagespeed = (import 'github.com/thaum-xyz/jsonnet-libs/apps/pagespeed/pagespeed.libsonnet');
local kubeEventsExporter = (import 'github.com/thaum-xyz/jsonnet-libs/apps/kube-events-exporter/kube-events-exporter.libsonnet');
local pushgateway = (import 'github.com/thaum-xyz/jsonnet-libs/apps/pushgateway/pushgateway.libsonnet');

local ingressAnnotations = {
  'kubernetes.io/ingress.class': 'nginx',
  'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
  'nginx.ingress.kubernetes.io/auth-url': 'https://auth.ankhmorpork.thaum.xyz/oauth2/auth',
  'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.ankhmorpork.thaum.xyz/oauth2/start?rd=$scheme://$host$escaped_request_uri',
};

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') +
  // (import 'lib/ingress.libsonnet') +
  // TODO: Can be enabled after dealing with lancre ENV
  // (import 'lib/additional-scrape-configs.libsonnet') +
  // (import './lib/k3s.libsonnet') +
  // (import './config.json') +
  {
    //
    // Configuration
    //

    // TODO: figure out how to make this a JSON/YAML file!
    values+:: (import './config.jsonnet'),

    //
    // Objects customization
    // kube-prometheus objects first
    //

    alertmanager+: {
      // alertmanager secret is stored as ConfigMapSecret in plain yaml file
      secret:: null,
      // TODO: move ingress and externalURL to an addon
      alertmanager+: {
        spec+: {
          externalUrl: 'https://alertmanager.' + $.values.common.baseDomain,
        },
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

    // TODO: Should service expose 2 ports???
    blackboxExporter+: {
      deployment+: {
        spec+: {
          template+: {
            metadata+: {
              annotations+: {
                'kubectl.kubernetes.io/default-container': 'blackbox-exporter',
              },
            },
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
          // TODO: Move this to addon when lancre is dealt with
          // additionalScrapeConfigs are stored as ConfigMapSecret in plain yaml file
          additionalScrapeConfigs: {
            name: 'scrapeconfigs',
            key: 'additional.yaml',
          },
          queryLogFile: '/prometheus/query.log',

          enableFeatures: ['remote-write-receiver'],

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
                rule { expr: '100 * (count(up{job!="windows",instance!="biuro.lancre.thaum.xyz:9100"} == 0) BY (job, namespace, service) / count(up{job!="windows",instance!="biuro.lancre.thaum.xyz:9100"}) BY (job, namespace, service)) > 10' }
              else rule,
              ruleGroup.rules,
            ),
          }, super.groups),
        },
      },
    },

    grafana+: (import 'lib/grafana-overrides.libsonnet'),

    //
    // Custom components
    //

    kubeEventsExporter: kubeEventsExporter($.values.kubeEventsExporter),
    pushgateway: pushgateway($.values.pushgateway),
    // TODO: uncomment when https://github.com/prometheus-operator/prometheus-operator/pull/4074 is done and released
    //pagespeed: pagespeed($.values.pagespeed) + {
    //  deployment+: {
    //    spec+: {
    //      template+: {
    //        spec+: {
    //          nodeSelector+: {
    //            'kubernetes.io/os': 'linux',
    //            'kubernetes.io/arch': 'amd64',
    //          },
    //        },
    //      },
    //    },
    //  },
    //},
    // TODO: rebuild exporter to be arm64 compliant
    //uptimerobot: exporter($.values.uptimerobot) + {
    //  secret: sealedsecret(
    //    {
    //      name: $.values.uptimerobot.secretRefName,
    //      namespace: $.values.common.namespace,
    //    },
    //    { UPTIMEROBOT_API_KEY: $.values.uptimerobot.encryptedApiKey }
    //  ),
    //  deployment+: {
    //    spec+: {
    //      template+: {
    //        spec+: {
    //          nodeSelector+: {
    //            'kubernetes.io/os': 'linux',
    //            'kubernetes.io/arch': 'amd64',
    //          },
    //        },
    //      },
    //    },
    //  },
    //  podMonitor+: {
    //    spec+: {
    //      podMetricsEndpoints: [{ port: 'http', interval: '5m' }],
    //    },
    //  },
    //},
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

    sloth: sloth($.values.sloth),

    other: {
      local externalRules = import 'lib/externalRules.libsonnet',
      thaumPrometheusRule: externalRules({
        name: 'thaum-rules',
        groups: (import 'ext/rules/thaum.json').groups,
      }),
      testingPrometheusRule: externalRules({
        name: 'testing-rules',
        groups: (import 'ext/rules/testing.json').groups,
      }),
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
