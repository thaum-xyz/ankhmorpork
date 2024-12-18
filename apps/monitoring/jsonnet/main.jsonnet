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
//       - go runtime metrics (https://github.com/grafana/jsonnet-libs/tree/master/go-runtime-mixin)
//     from json:
//       - blackbox-exporter
//       - smokeping
//       - unifi
//       - nginx-controller
//       - mysql (x2)
//       - redis
//       - home dashboard

local parcaEnable = {
  annotations+: {
    'parca.dev/scrape': 'true',
  },
};

local ingress(metadata, domain, service) = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'Ingress',
  metadata: metadata {
    annotations+: {
      // Add those annotations to every ingress so oauth-proxy is used.
      'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
      'traefik.ingress.kubernetes.io/router.middlewares': 'auth-traefik-forward-auth@kubernetescrd',
      'reloader.homer/group': 'Administration',
      'reloader.homer/logo': 'https://github.com/cncf/artwork/blob/main/projects/prometheus/icon/color/prometheus-icon-color.png?raw=true',  // Default to prometheus logo
      'reloader.homer/name': $.metadata.name,
      'probe-uri': '/-/healthy',
    },
    labels+: {
      'reloader.homer/enabled': 'true',
    },
  },
  spec: {
    tls: [{
      hosts: [domain],
      secretName: metadata.name + '-tls',
    }],
    ingressClassName: 'public',
    rules: [{
      host: domain,
      http: {
        paths: [{
          path: '/',
          pathType: 'Prefix',
          backend: {
            service: service,
          },
        }],
      },
    }],
  },
};

// FIXME: solve in https://github.com/prometheus-operator/kube-prometheus/issues/1719
local allowIngressNetworkPolicy(port) = {
  spec+: {
    ingress+: [{
      from: [{
        podSelector: {
          matchLabels: {
            'app.kubernetes.io/name': 'ingress-nginx',
          },
        },
        namespaceSelector: {
          matchLabels: {
            'kubernetes.io/metadata.name': 'ingress-nginx',
          },
        },
      }],
      ports: [{
        port: port,
        protocol: 'TCP',
      }],
    }],
  },
};

local exporter = (import 'apps/prometheus-exporter.libsonnet');
local externalsecret = (import 'utils/externalsecrets.libsonnet').externalsecret;
local addArgs = (import 'utils/container.libsonnet').addArgs;
local addContainerParameter = (import 'utils/container.libsonnet').addContainerParameter;
local removeAlert = (import 'utils/mixins.libsonnet').removeAlert;
local removeAlerts = (import 'utils/mixins.libsonnet').removeAlerts;
local probe = (import 'utils/prometheus-crs.libsonnet').probe;
local pod = (import 'utils/pod.libsonnet');
local pushgateway = (import 'lib/pushgateway.libsonnet');

local windows = (import 'lib/windows-exporter.libsonnet');
local jsonExporter = (import 'lib/json-exporter.libsonnet');

local githubReceiver = (import 'lib/github-receiver.libsonnet');

local mixin = (import 'kube-prometheus/lib/mixin.libsonnet');

local kp =
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/main.libsonnet') +
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/addons/all-namespaces.libsonnet') +
  (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/addons/pyrra.libsonnet') +
  // (import 'github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus/addons/windows.libsonnet') +
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
            metadata+: parcaEnable,
            spec+: {
              containers: addArgs($.values.prometheusOperator.extraArgs, 'prometheus-operator', super.containers),
            },
          },
        },
      },
    },

    alertmanager+: {
      configTemplate: {
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: $.alertmanager.alertmanager.metadata {
          name: 'alertmanager-config-template',
        },
        data: {
          'alertmanager.yaml': (importstr '../raw/alertmanager-config.yaml.gtpl'),
        },
      },
      secret: externalsecret(
        $.alertmanager.alertmanager.metadata {
          name: 'alertmanager-main',
        },
        'doppler-auth-api',
        $.values.alertmanager.credentialsRefs,
      ) + {
        spec+: {
          target+: {
            template+: {
              templateFrom: [{
                configMap: {
                  name: $.alertmanager.configTemplate.metadata.name,
                  items: [{
                    key: std.objectFields($.alertmanager.configTemplate.data)[0],
                  }],
                },
              }],
            },
          },
        },
      },
      // TODO: move ingress and externalURL to an addon in kube-prometheus
      alertmanager+: {
        spec+: {
          podMetadata+: parcaEnable,
          externalUrl: 'https://alertmanager.' + $.values.common.baseDomain,
        },
      },
      service+: {
        metadata+: {
          annotations+: {
            'traefik.ingress.kubernetes.io/service.sticky.cookie': 'true',
          },
        },
      },
      podDisruptionBudget+: {
        spec+: {
          // Allow cluster drain even if alertmanager eviction cannot be completed
          unhealthyPodEvictionPolicy: 'AlwaysAllow',
        },
      },

      // FIXME: solve in https://github.com/prometheus-operator/kube-prometheus/issues/1719
      networkPolicy+:: allowIngressNetworkPolicy($.alertmanager.service.spec.ports[0].port),
      ingress: ingress(
        $.alertmanager.service.metadata {
          name: 'alertmanager',  // FIXME: that's an artifact from previous configuration, it should be removed.
        },
        'alertmanager.' + $.values.common.baseDomain,
        {
          name: $.alertmanager.service.metadata.name,
          port: {
            name: $.alertmanager.service.spec.ports[0].name,
          },
        },
      ),
    },

    blackboxExporter+: {
      serviceMonitor+: {
        spec+: {
          endpoints: std.map(
            function(e) if e.port == 'https' then
              e {
                interval: '120s',
                scrapeTimeout: '120s',
              }
            else e,
            super.endpoints
          ),
        },
      },
      deployment+: {
        spec+: {
          template+: {
            metadata+: parcaEnable,
            spec+: {
              affinity: pod.antiaffinity('blackbox-exporter'),
              dnsPolicy: 'None',
              dnsConfig: {
                nameservers: ['192.168.2.4'],
                searches: ['thaum.xyz'],
              },
            },
          },
        },
      },
      local probeMetadata = {
        namespace: $.blackboxExporter.deployment.metadata.namespace,
        labels: $.blackboxExporter._config.commonLabels,
      },
      local prober = {
        url: 'blackbox-exporter.' + $.values.common.namespace + '.svc:19115',
      },
      thaumProbe: probe(
        probeMetadata { name: 'thaum-sites' },
        prober,
        'http_2xx',
        $.values.blackboxExporter.probes.thaumSites
      ),
      ingressProbe: probe(
        probeMetadata { name: 'ingress' },
        prober,
        'http_2xx',
        $.values.blackboxExporter.probes.ingress
      ) + {
        spec+: {
          tlsConfig: {
            insecureSkipVerify: true,
          },
        },
      },
    },

    nodeExporter+: {
      serviceMonitor+: {
        spec+: {
          endpoints: std.map(
            function(e) if e.port == 'https' then
              e {
                interval: '120s',
                scrapeTimeout: '120s',
                relabelings+: [{
                  action: 'replace',
                  regex: '(.*)',
                  replacement: '$1',
                  sourceLabels: ['__meta_kubernetes_pod_node_name'],
                  targetLabel: 'node',
                }],
              }
            else e,
            super.endpoints
          ),
        },
      },
      prometheusRule+: {
        spec+: {
          groups: std.map(function(ruleGroup) ruleGroup {
            rules: std.map(
              function(rule) if 'alert' in rule && rule.alert == 'NodeClockNotSynchronising' then
                rule { expr: 'min_over_time(node_timex_sync_status{job="node-exporter",instance!~"qnap.*"}[5m]) == 0 and node_timex_maxerror_seconds{job="node-exporter",instance!~"qnap.*"} >= 16' }
              else rule,
              ruleGroup.rules,
            ),
          }, super.groups),
        },
      },
      daemonset+: {
        spec+: {
          template+: {
            metadata+: parcaEnable,
            spec+: {
              containers: std.map(
                function(c) if c.name == 'node-exporter' then
                  c {
                    args+: ['--collector.textfile.directory=/host/textfile'],
                    volumeMounts+: [{
                      mountPath: '/host/textfile',
                      mountPropagation: 'HostToContainer',
                      name: 'textfile',
                      readOnly: true,
                    }],
                  }
                else c,
                super.containers
              ),
              volumes+: [{
                hostPath: {
                  path: '/var/lib/node_exporter',
                },
                name: 'textfile',
              }],
            },
          },
        },
      },
    },

    // Using metrics-server instead of prometheus-adapter
    prometheusAdapter:: null,

    prometheus+: {
      service+: {
        metadata+: {
          annotations+: {
            'traefik.ingress.kubernetes.io/service.sticky.cookie': 'true',
          },
        },
      },
      prometheus+: {
        spec+: {
          // TODO: move ingress and externalURL to an addon
          externalUrl: 'https://prometheus.' + $.values.common.baseDomain,
          retention: '33d',
          retentionSize: '35GB',
          affinity+: $.values.prometheus.affinity,

          podMetadata+: parcaEnable,
          // FIXME: reenable
          securityContext:: null,

          // TODO: expose remoteWrite as a top-level config in kube-prometheus
          remoteWrite: [{
            url: 'http://thanos-receive.datalake-metrics.svc:19291/api/v1/receive',
            writeRelabelConfigs: [
              {
                sourceLabels: ['__name__'],
                regex: '^apiserver_.*|longhorn_.*|workqueue_.*|etcd_.*|nginx_.*|storage_operation_.*|rest_client_.*|cnpg_pg_settings_setting|container_memory_failures_total',
                action: 'drop',
              },
            ],
          }],

          // remoteRead: [{
          //   url: "http://mimir.mimir.svc:9009/prometheus/api/v1/read",
          // }],
          enforcedNamespaceLabel: 'namespace',
          excludedFromEnforcement: [
            //{
            //  resource: 'probes',
            //  namespace: $.values.common.namespace,
            //  name: 'ingress',
            //},
            {
              resource: 'servicemonitors',
              namespace: $.values.common.namespace,
              name: 'kube-state-metrics',
            },
            {
              resource: 'scrapeconfigs',
              namespace: $.values.common.namespace,
              name: 'kubelet',
            },
            {
              resource: 'scrapeconfigs',
              namespace: $.values.common.namespace,
              name: 'kubelet-cadvisor',
            },
            {
              resource: 'scrapeconfigs',
              namespace: $.values.common.namespace,
              name: 'kubelet-probes',
            },
            {
              resource: 'scrapeconfigs',
              namespace: $.values.common.namespace,
              name: 'kubelet-slis',
            },
            {
              resource: 'servicemonitors',
              namespace: $.values.common.namespace,
              name: 'node-exporter',
            },
            {
              resource: 'servicemonitors',
              namespace: $.values.common.namespace,
              name: 'blackbox-exporter',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'kube-prometheus-rules',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'kube-state-metrics-rules',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'node-exporter-rules',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'kubernetes-monitoring-rules',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'apiserver-read-resource-latency',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'apiserver-write-response-errors',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'apiserver-read-cluster-latency',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'apiserver-read-response-errors',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'apiserver-read-namespace-latency',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'kubelet-runtime-errors',
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
              name: 'kubelet-request-errors',
            },
            {
              resource: 'prometheusrules',
              namespace: 'cnpg-system',
            },
            {
              resource: 'servicemonitors',
              namespace: 'cert-manager',
            },
            {
              resource: 'prometheusrules',
              namespace: 'cert-manager',
            },
            {
              resource: 'podmonitors',
              namespace: 'flux-system',
            },
            {
              resource: 'prometheusrules',
              namespace: 'flux-system',
            },
          ],
          storage: {
            volumeClaimTemplate: {
              metadata: {
                name: 'prometheus',
              },
              spec: {
                storageClassName: 'lvm-thin',  // For performance reasons use local disk
                accessModes: ['ReadWriteOnce'],
                resources: {
                  requests: { storage: '40Gi' },
                },
              },
            },
          },
        },
      },
      serviceAccountToken: {
        apiVersion: 'v1',
        kind: 'Secret',
        metadata: $.prometheus.serviceAccount.metadata {
          name: $.prometheus.serviceAccount.metadata.name + '-token',
          annotations: {
            'kubernetes.io/service-account.name': $.prometheus.serviceAccount.metadata.name,
          },
        },
        type: 'kubernetes.io/service-account-token',
      },
      clusterRole+: {
        rules+: [{
          apiGroups: [''],
          resources: ['nodes'],
          verbs: ['get', 'list', 'watch'],
        }],
      },
      // FIXME: solve in https://github.com/prometheus-operator/kube-prometheus/issues/1719
      networkPolicy+:: allowIngressNetworkPolicy($.prometheus.service.spec.ports[0].port),
      ingress: ingress(
        $.prometheus.service.metadata,
        'prometheus.' + $.values.common.baseDomain,
        {
          name: $.prometheus.service.metadata.name,
          port: {
            name: $.prometheus.service.spec.ports[0].name,
          },
        },
      ),
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
      serviceMonitor+: {
        spec+: {
          endpoints: std.map(
            function(e)
              // Add `kube-system` as namespace label for `kube_node_*` metrics
              // This is done to make sure all metrics have some sort of a namespace label
              // so it won't be problematic in alerting stage
              if e.port == 'https-main' then
                e {
                  metricRelabelings+: [{
                    regex: 'kube_node_.*',
                    replacement: 'kube-system',
                    targetLabel: 'namespace',
                  }],
                }
              else e,
            super.endpoints,
          ),
        },
      },
    },

    kubernetesControlPlane+: {
      // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
      serviceMonitorApiserver:: null,
      serviceMonitorKubeControllerManager:: null,
      serviceMonitorKubeScheduler:: null,
      podMonitorKubeProxy:: null,
      serviceMonitorKubelet+:: {},  // Migrating to ScrapeConfig
      local backwardsCompatibilityLabels = [
        {
          action: 'replace',
          replacement: 'kube-system',
          targetLabel: 'namespace',
        },
        {
          action: 'replace',
          sourceLabels: ['__meta_kubernetes_node_name'],
          targetLabel: 'node',
        },
        {
          sourceLabels: ['__metrics_path__'],
          targetLabel: 'metrics_path',
        },
      ],
      scrapeConfigKubelet: {
        apiVersion: 'monitoring.coreos.com/v1alpha1',
        kind: 'ScrapeConfig',
        metadata: $.kubernetesControlPlane.serviceMonitorKubelet.metadata {
          name: 'kubelet',
        },
        spec: {
          authorization: {
            credentials: {
              key: 'token',
              name: 'prometheus-k8s-token',
            },
            type: 'Bearer',
          },
          honorLabels: true,
          kubernetesSDConfigs: [{ role: 'Node' }],
          metricRelabelings: $.kubernetesControlPlane.serviceMonitorKubelet.spec.endpoints[0].metricRelabelings,
          metricsPath: '/metrics',
          relabelings: backwardsCompatibilityLabels + [{
            targetLabel: 'job',
            replacement: 'kubelet',
          }],
          scheme: 'HTTPS',
          scrapeInterval: '30s',
          tlsConfig: {
            insecureSkipVerify: true,
          },
        },
      },
      scrapeConfigKubeletCadvisor: $.kubernetesControlPlane.scrapeConfigKubelet {
        metadata+: {
          name: 'kubelet-cadvisor',
        },
        spec+: {
          honorLabels: true,
          honorTimestamps: false,
          metricRelabelings: $.kubernetesControlPlane.serviceMonitorKubelet.spec.endpoints[1].metricRelabelings,
          metricsPath: '/metrics/cadvisor',
        },
      },
      scrapeConfigKubeletProbes: $.kubernetesControlPlane.scrapeConfigKubelet {
        metadata+: {
          name: 'kubelet-probes',
        },
        spec+: {
          honorLabels: true,
          metricsPath: '/metrics/probes',
          metricRelabelings:: [],
          scrapeInterval: '30s',
        },
      },
      scrapeConfigKubeletSLIs: $.kubernetesControlPlane.scrapeConfigKubelet {
        metadata+: {
          name: 'kubelet-slis',
        },
        spec+: {
          honorLabels: true,
          metricsPath: '/metrics/slis',
          metricRelabelings:: [],
          scrapeInterval: '5s',
          scrapeTimeout: '5s',
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
                // FIXME: possibly port to kube-prometheus
                rule { expr: '100 * (count(up{job!="windows-exporter"} == 0) BY (job, namespace) / count(up{job!="windows-exporter"}) BY (job, namespace)) > 50' }
              else rule,
              ruleGroup.rules,
            ),
          }, super.groups),
        },
      },
    },

    pyrra+: {
      ingress: ingress(
        $.pyrra.apiService.metadata,
        'pyrra.' + $.values.common.baseDomain,
        {
          name: $.pyrra.apiService.metadata.name,
          port: {
            name: $.pyrra.apiService.spec.ports[0].name,
          },
        },
      ) + {
        metadata+: {
          annotations+: {
            'reloader.homer/logo': 'https://avatars.githubusercontent.com/u/87393422?s=200&v=4',
            'reloader.homer/name': 'pyrra',
          },
        },
      },
      // TODO: Remove this when https://github.com/prometheus-operator/kube-prometheus/issues/1718 is finished
      apiDeployment+: {
        spec+: {
          template+: {
            metadata+: parcaEnable,
            spec+: {
              containers: addContainerParameter(
                'resources',
                $.values.pyrra.resources,
                'pyrra',
                addArgs(['--prometheus-external-url=https://prometheus.ankhmorpork.thaum.xyz'], 'pyrra', super.containers)
              ),
            },
          },
        },
      },
      kubernetesDeployment+: {
        spec+: {
          template+: {
            metadata+: parcaEnable,
            spec+: {
              containers: addContainerParameter(
                'resources',
                $.values.pyrra.resources,
                'pyrra',
                super.containers
              ),
            },
          },
        },
      },
      'slo-coredns-response-errors'+: {
        spec+: {
          target: '99.9',
        },
      },
      'slo-prometheus-query-errors'+: {
        spec+: {
          target: '95.0',
          window: '4w',
        },
      },
    } + (import 'lib/slo-apiserver.libsonnet'),

    grafana+: {
      config+:: {},
      dashboardSources+:: {},
      //dashboardDefinitions:: {},
      deployment+: {
        spec+: {
          template+: {
            metadata+: parcaEnable,
            spec+: {
              containers: std.map(
                function(c) c {
                  volumeMounts: [
                    {
                      mountPath: '/var/lib/grafana',
                      name: 'grafana-storage',
                    },
                    {
                      mountPath: '/etc/grafana/provisioning/datasources',
                      name: 'grafana-datasources',
                    },
                    {
                      mountPath: '/tmp',
                      name: 'tmp',
                    },
                  ],
                }, super.containers,
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
                    claimName: $.grafana.pvc.metadata.name,
                  },
                },
                {
                  name: 'grafana-datasources',
                  secret: {
                    secretName: 'grafana-datasources',
                  },
                },
                {
                  name: 'tmp',
                  emptyDir: {},
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
          name: 'grafana-app-data',
          namespace: $.grafana.deployment.metadata.namespace,
        },
        spec: {
          storageClassName: 'qnap-nfs',
          accessModes: ['ReadWriteOnce'],
          resources: {
            requests: {
              storage: '60Mi',
            },
          },
        },
      },

      // FIXME: solve in https://github.com/prometheus-operator/kube-prometheus/issues/1719
      networkPolicy+:: allowIngressNetworkPolicy($.grafana.service.spec.ports[0].port),
      ingress: ingress(
        $.grafana.service.metadata,
        'grafana.' + $.values.common.baseDomain,
        {
          name: $.grafana.service.metadata.name,
          port: {
            name: $.grafana.service.spec.ports[0].name,
          },
        },
      ) + {
        metadata+: {
          annotations+: {
            'reloader.homer/logo': 'https://grafana.com/static/img/logos/grafana_logo_swirl-events.svg',
          },
        },
      },
    },

    //
    // Custom components
    //
    external: {
      nodeScrapeConfig: {
        apiVersion: 'monitoring.coreos.com/v1alpha1',
        kind: 'ScrapeConfig',
        metadata: {
          name: 'node-exporter-external',
          namespace: $.values.common.namespace,
        },
        spec: {
          scrapeInterval: '15s',
          staticConfigs: [
            {
              targets: [
                'dns.ankhmorpork.thaum.xyz:9100',
              ],
              labels: {
                pod: 'dns1',
                node: 'dns.ankhmorpork.thaum.xyz',
              },
            },
            {
              targets: [
                'qnap.ankhmorpork.thaum.xyz:9100',
              ],
              labels: {
                pod: 'qnap',
                node: 'qnap.ankhmorpork.thaum.xyz',
              },
            },
          ],
          relabelings: [{
            sourceLabels: ['__name__'],
            targetLabel: 'job',
            replacement: 'node-exporter',
          }],
          metricRelabelings: [{
            action: 'drop',
            regex: 'node_md_disks_required(md9|md13)',
            sourceLabels: ['__name__', 'device'],
          }],
        },
      },
    },

    githubReceiver: githubReceiver($.values.githubReceiver) + {
      credentials: externalsecret(
        $.githubReceiver.deployment.metadata {
          name: $.values.githubReceiver.githubTokenSecretName,
        },
        'doppler-auth-api',
        {
          ATG_GITHUB_TOKEN: $.values.githubReceiver.githubTokenRef,
        }
      ),
    },

    windowsExporter: windows($.values.windowsExporter),

    pushgateway: pushgateway($.values.pushgateway),
    smokeping: exporter($.values.smokeping) + {
      deployment+: {
        spec+: {
          template+: {
            metadata+: parcaEnable,
            spec+: {
              affinity: pod.antiaffinity('smokeping'),
              containers: std.map(function(c) c {
                securityContext: { capabilities: { add: ['NET_RAW'] } },
              }, super.containers),
            },
          },
        },
      },
    },

    uptimerobot: jsonExporter($.values.uptimerobot) + {
      deployment+: {
        spec+: {
          template+: {
            metadata+: parcaEnable {
              annotations+: {
                'checksum.config/md5': std.md5($.values.uptimerobot.config),
              },
            },
          },
        },
      },
      configuration: externalsecret(
        $.uptimerobot.deployment.metadata,
        'doppler-auth-api',
        $.values.uptimerobot.credentials
      ) + {
        spec+: {
          target+: {
            template+: {
              engineVersion: 'v2',
              data: {
                'config.yml': $.values.uptimerobot.config,
              },
            },
          },
        },
      },
    },

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
      ingresSLO: {
        apiVersion: 'pyrra.dev/v1alpha1',
        kind: 'ServiceLevelObjective',
        metadata: {
          name: 'blackbox-probe-success',
          namespace: 'monitoring',
        },
        spec: {
          target: '95.0',
          window: '7d',
          indicator: {
            bool_gauge: {
              metric: 'probe_success',
              grouping: ['instance'],
            },
          },
        },
      },
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
