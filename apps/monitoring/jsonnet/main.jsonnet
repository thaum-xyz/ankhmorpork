// TODO list:
// - compare and test

// k3s additions:
// - kube-controller-manager-prometheus-discovery service
// - kube-scheduler-prometheus-discovery

// Things to fix in kube-prometheus
// - better examples for adding custom alerts/rules
// - addon/example for additionalScrapeConfigs?
// - prometheus-pvc should be an addon
// - better `examples/` directory schema
// - addon to add 'runbook_url' annotation to every alert
// - non-prometheus ServiceMonitors shouldn't be in prometheus object
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

// convert file to yaml when jsonnet supports yaml imports (https://github.com/google/jsonnet/pull/888)
local blackboxExporterModules = (import 'ext/blackboxExporterConfig.json').modules;

// TODO: add to kube-prometheus, more info in libsonnet file
local kubeEventsExporter = (import 'lib/kube-events-exporter.libsonnet');
// TODO: add to kube-prometheus, more info in libsonnet file
local pushgateway = (import 'lib/pushgateway.libsonnet');
// TODO: consider moving this to some other place (maybe jsonnet-libs repo?)
local smokeping = (import 'lib/smokeping.libsonnet');
// TODO: consider moving this to some other place (maybe jsonnet-libs repo?)
local uptimerobot = (import 'lib/uptimerobot-exporter.libsonnet');

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
    values+:: {
      common+: {
        namespace: 'monitoring',
        ruleLabels: {
          role: 'alert-rules',
        },
        baseDomain: 'ankhmorpork.thaum.xyz',
      },
      kubeEventsExporter: {
        namespace: $.values.common.namespace,
        version: '0.1.0',
        image: 'quay.io/dgrisonnet/kube-events-exporter:v0.1.0',
        resources: {
          requests: { cpu: '2m', memory: '16Mi' },
        },
        commonLabels+: {
          'app.kubernetes.io/component': 'exporter',
        },
      },
      pushgateway: {
        namespace: $.values.common.namespace,
        version: '1.2.0',
        image: 'quay.io/prometheus/pushgateway:v1.2.0',
        resources: {
          requests: { cpu: '10m', memory: '12Mi' },
        },
      },
      smokeping: {
        namespace: $.values.common.namespace,
        version: '1.2.0',
        image: 'quay.io/superq/smokeping-prober:v0.4.1',
        resources: {
          requests: { cpu: '40m', memory: '30Mi' },
          limits: { memory: '70Mi' },
        },
        replicas: 2,
        hosts: [
          '8.8.8.8',
          '1.1.1.1',
          'lancre.thaum.xyz',
          'krupa.net.pl',
          'cloud.krupa.net.pl',
          'pawel.krupa.net.pl',
        ],
      },
      uptimerobot: {
        namespace: $.values.common.namespace,
        version: 'latest',
        // TODO: consider rewriting/updating this exporter
        image: 'drubin/uptimerobot-prometheus-exporter',
        // TODO: adjust resource requirements
        resources: {
          requests: { cpu: '40m', memory: '30Mi' },
          limits: { memory: '70Mi' },
        },
        port: 9429,
        secretRefName: 'uptimerobot-api-key',
      },
      alertmanager+: {
        resources: {
          requests: { memory: '30Mi' },
        },
      },
      prometheus+: {
        version: '2.26.0',
        image: 'quay.io/prometheus/prometheus:v2.26.0',
        resources: {
          requests: { cpu: '140m', memory: '1900Mi' },
          limits: { cpu: '1' },
        },
      },
      prometheusOperator+: {
        mixin+: {
          _config: {
            prometheusOperatorSelector: 'job="prometheus-operator"',
          },
        },
      },
      blackboxExporter+: {
        modules: blackboxExporterModules,
        resources: {
          requests: { cpu: '30m', memory: '16Mi' },
          limits: { cpu: '64m', memory: '42Mi' },
        },
        replicas: 2,
        probes: {
          promDemo: {
            staticConfig: {
              static: [
                'https://demo.do.prometheus.io',
                'https://prometheus.demo.do.prometheus.io/-/healthy',
                'https://alertmanager.demo.do.prometheus.io/-/healthy',
                'https://node.demo.do.prometheus.io',
                'https://grafana.demo.do.prometheus.io/api/health',
              ],
              labels: { environment: 'prometheus.io' },
            },
          },
          thaumSites: {
            staticConfig: {
              static: [
                'https://weirdo.blog/ghost',
                'https://alchemyof.it/ghost',
                'https://zmc.krupa.net.pl',
              ],
              labels: { environment: 'thaum.xyz' },
            },
          },
          ingress: {
            ingress: {
              selector: {
                matchLabels: {
                  probe: 'enabled',
                },
              },
              namespaceSelector: { any: true },
            },
          },
        },
      },
      kubeStateMetrics+: {
        version: 'v2.0.0',
        image: 'k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.0.0',
      },
      grafana+: {
        version: '7.5.3',
        //image: 'grafana/grafana:7.5.3', // This is overridden in grafana-overrides.libsonnet
        datasources: [{
          name: 'Prometheus',
          type: 'prometheus',
          access: 'proxy',
          orgId: 1,
          isDefault: true,
          url: 'http://prometheus-k8s.monitoring.svc:9090',
        }],
      },
      kubernetesControlPlane+: {
        mixin+: {
          _config+: {
            // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
            kubeSchedulerSelector: 'job="kubelet"',
            kubeControllerManagerSelector: 'job="kubelet"',
            kubeApiserverSelector: 'job="kubelet"',
            cpuThrottlingPercent: 70,
          },
        },
      },
    },

    //
    // Objects customization
    //
    kubeEventsExporter: kubeEventsExporter($.values.kubeEventsExporter),
    pushgateway: pushgateway($.values.pushgateway),
    // TODO: rebuild exporter to be arm64 compliant
    uptimerobot: uptimerobot($.values.uptimerobot) + {
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
    smokeping: smokeping($.values.smokeping) + {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              affinity: (import '../../../lib/podantiaffinity.libsonnet').podantiaffinity('smokeping'),
            },
          },
        },
      },
    },

    local ingressAnnotations = {
      'kubernetes.io/ingress.class': 'nginx',
      'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
      'nginx.ingress.kubernetes.io/auth-url': 'https://auth.ankhmorpork.thaum.xyz/oauth2/auth',
      'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.ankhmorpork.thaum.xyz/oauth2/start?rd=$scheme://$host$escaped_request_uri',
    },
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
          namespace: $.values.common.namespace,
          annotations: ingressAnnotations,
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
              affinity: (import '../../../lib/podantiaffinity.libsonnet').podantiaffinity('blackbox-exporter'),
            },
          },
        },
      },
      promDemoProbe: probe('prometheus-demo', $.values.common.namespace, $.blackboxExporter._config.commonLabels, 'http_2xx', $.values.blackboxExporter.probes.promDemo),
      thaumProbe: probe('thaum-sites', $.values.common.namespace, $.blackboxExporter._config.commonLabels, 'http_2xx', $.values.blackboxExporter.probes.thaumSites),
      ingressProbe: probe('ankhmorpork', $.values.common.namespace, $.blackboxExporter._config.commonLabels, 'http_2xx', $.values.blackboxExporter.probes.ingress),
    },
    prometheusOperator+: {
      deployment+: {
        spec+: {
          template+: {
            metadata+: {
              annotations+: {
                'kubectl.kubernetes.io/default-container': 'prometheus-operator',
              },
            },
            spec+: {
              containers: addArgs(['--config-reloader-cpu=150m', '--log-level=debug'], 'prometheus-operator', super.containers),
            },
          },
        },
      },
    },
    prometheus+: {
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
          // TODO: figure out why this is not added by default
          ruleNamespaceSelector: {},
          ruleSelector: {},

          // TODO: remove after https://github.com/prometheus-operator/kube-prometheus/pull/929 is merged
          thanos:: null,
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
          namespace: $.values.common.namespace,
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
      // TODO: check if this addition is necessary
      clusterRole+: {
        rules+: [{
          apiGroups: ['networking.k8s.io'],
          resources: ['ingresses'],
          verbs: ['get', 'list', 'watch'],
        }],
      },
      // TODO: those should be a part of kube-prometheus/addons/all-namespaces.libsonnet
      roleBindingSpecificNamespaces:: null,
      roleSpecificNamespaces:: null,
    },
    kubeStateMetrics+: {
      deployment+: {
        spec+: {
          template+: {
            metadata+: {
              annotations+: {
                'kubectl.kubernetes.io/default-container': 'kube-state-metrics',
              },
            },
            spec+: {
              containers:
                // addArgs(['--metric-labels-allowlist=nodes=[kubernetes.io/arch,gpu.infra/intel,network.infra/type]'], 'kube-state-metrics', super.containers) +
                // TODO: consider moving this into kube-prometheus
                std.map(
                  function(c) if c.name == 'kube-rbac-proxy-main' then
                    c {
                      resources+: {
                        requests+: { cpu: '40m' },
                        limits+: { cpu: '60m' },
                      },
                    }
                  else if c.name == 'kube-state-metrics' then
                    c {
                      args+: ['--metric-labels-allowlist=nodes=[kubernetes.io/arch,gpu.infra/intel,network.infra/type]'],
                    }
                  else c,
                  super.containers,
                ),
            },
          },
        },
      },
    },
    grafana+: (import 'lib/grafana-overrides.libsonnet'),
    other: {
      local externalRules = import 'lib/externalRules.libsonnet',
      coreDNSMixin:: (import 'github.com/povilasv/coredns-mixin/mixin.libsonnet') + {
        _config+:: {
          corednsSelector: 'job=~"kube-dns|coredns"',
          corednsRunbookURLPattern: 'https://github.com/thaum-xyz/ankhmorpork/tree/master/docs/runbooks/%s',
        },
      },
      coreDNSPrometheusRule: externalRules({
        name: 'coredns',
        groups: $.other.coreDNSMixin.prometheusAlerts.groups,
      }),
      thaumPrometheusRule: externalRules({
        name: 'thaum-rules',
        groups: (import 'ext/rules/thaum.json').groups,
      }),
      testingPrometheusRule: externalRules({
        name: 'testing-rules',
        groups: (import 'ext/rules/testing.json').groups,
      }),
    },

    kubernetesControlPlane+: {
      // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
      serviceMonitorApiserver:: null,
      serviceMonitorKubeControllerManager:: null,
      serviceMonitorKubeScheduler:: null,
      // TODO: fix in kube-prometheus
      serviceMonitorCoreDNS+: {
        metadata+: {
          labels+: {
            'k8s-app': 'kube-dns',
          },
        },
        spec+: {
          jobLabel: 'k8s-app',
          selector: {
            matchLabels: {
              'k8s-app': 'kube-dns',
            },
          },
        },
      },
      serviceMonitorKubelet+: {
        spec+: {
          endpoints+: [
            // Scrape new /metrics/resource kubelet endpoint. TODO: move to kube-prometheus
            {
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              honorLabels: true,
              interval: '30s',
              metricRelabelings: [{
                action: 'drop',
                regex: 'container_(network_tcp_usage_total|network_udp_usage_total|tasks_state|cpu_load_average_10s)',
                sourceLabels: ['__name__'],
              }],
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
                rule { expr: '100 * (count(up{job!="windows"} == 0) BY (job, namespace, service) / count(up{job!="windows"}) BY (job, namespace, service)) > 10' }
              else rule,
              ruleGroup.rules,
            ),
          }, super.groups),
        },
      },
    },
  } +
  // kube-linter annotations need to be added after all objects are created
  (import 'lib/kube-linter.libsonnet');

//
// Manifestation
//
{ 'namespace.yaml': std.manifestYamlDoc(kp.kubePrometheus.namespace) } +
{ ['prometheus-operator/' + name + '.yaml']: std.manifestYamlDoc(kp.prometheusOperator[name]) for name in std.objectFields(kp.prometheusOperator) } +
{ ['kube-state-metrics/' + name + '.yaml']: std.manifestYamlDoc(kp.kubeStateMetrics[name]) for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['alertmanager/' + name + '.yaml']: std.manifestYamlDoc(kp.alertmanager[name]) for name in std.objectFields(kp.alertmanager) } +
{ ['prometheus/' + name + '.yaml']: std.manifestYamlDoc(kp.prometheus[name]) for name in std.objectFields(kp.prometheus) } +
{ ['prober/' + name + '.yaml']: std.manifestYamlDoc(kp.blackboxExporter[name]) for name in std.objectFields(kp.blackboxExporter) } +
// node_exporter is deployed separately via Ansible
// { ['node-exporter/' + name + '.yaml']: std.manifestYamlDoc(kp.nodeExporter[name]) for name in std.objectFields(kp.nodeExporter) } +
{ 'other/nodeExporterPrometheusRule.yaml': std.manifestYamlDoc(kp.nodeExporter.prometheusRule) } +
// using metrics-server instead of prometheus-adater
// { ['prometheus-adapter-' + name + '.yaml']: std.manifestYamlDoc(kp.prometheusAdapter[name]) for name in std.objectFields(kp.prometheusAdapter) } +
// TBD
{ ['grafana/' + name + '.yaml']: std.manifestYamlDoc(kp.grafana[name]) for name in std.objectFields(kp.grafana) } +
{ ['pushgateway/' + name + '.yaml']: std.manifestYamlDoc(kp.pushgateway[name]) for name in std.objectFields(kp.pushgateway) } +
{ ['smokeping/' + name + '.yaml']: std.manifestYamlDoc(kp.smokeping[name]) for name in std.objectFields(kp.smokeping) } +
{ ['uptimerobot/' + name + '.yaml']: std.manifestYamlDoc(kp.uptimerobot[name]) for name in std.objectFields(kp.uptimerobot) } +
// { ['holiday/' + name + '.yaml']: std.manifestYamlDoc(kp.holidayExporter[name]) for name in std.objectFields(kp.holidayExporter) } +
{ ['kube-events-exporter/' + name + '.yaml']: std.manifestYamlDoc(kp.kubeEventsExporter[name]) for name in std.objectFields(kp.kubeEventsExporter) } +
{ ['other/k8sControlPlane-' + name + '.yaml']: std.manifestYamlDoc(kp.kubernetesControlPlane[name]) for name in std.objectFields(kp.kubernetesControlPlane) } +
{ ['other/' + name + '.yaml']: std.manifestYamlDoc(kp.other[name]) for name in std.objectFields(kp.other) } +
{ 'other/kubePrometheusRule.yaml': std.manifestYamlDoc(kp.kubePrometheus.prometheusRule) } +
{}
