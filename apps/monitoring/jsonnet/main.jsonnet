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
      'nginx.ingress.kubernetes.io/auth-url': 'https://auth.ankhmorpork.thaum.xyz/oauth2/auth',
      'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.ankhmorpork.thaum.xyz/oauth2/start?rd=$scheme://$host$escaped_request_uri',
    },
  },
  spec: {
    tls: [{
      hosts: [domain],
      secretName: metadata.name + '-tls',
    }],
    ingressClassName: 'nginx',
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
local pushgateway = (import 'github.com/thaum-xyz/jsonnet-libs/apps/pushgateway/pushgateway.libsonnet');

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
              containers: addArgs(['--log-level=debug'], 'prometheus-operator', super.containers),
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
      serviceAccount+: {
        automountServiceAccountToken: false,  // TODO: move into kube-prometheus
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
          annotations: {
            'nginx.ingress.kubernetes.io/affinity': 'cookie',
            'nginx.ingress.kubernetes.io/affinity-mode': 'persistent',
            'nginx.ingress.kubernetes.io/session-cookie-hash': 'sha1',
            'nginx.ingress.kubernetes.io/session-cookie-name': 'routing-cookie',
          },
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
      promDemoProbe: probe(
        probeMetadata { name: 'prometheus-demo' },
        prober,
        'http_2xx',
        $.values.blackboxExporter.probes.promDemo
      ),
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
      ),
      ankhmorporkProbe: probe(
        probeMetadata { name: 'ankhmorpork' },
        prober,
        'http_2xx',
        $.values.blackboxExporter.probes.ankhmorpork
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
                rule { expr: 'min_over_time(node_timex_sync_status{job="node-exporter",instance!="qnap"}[5m]) == 0 and node_timex_maxerror_seconds{job="node-exporter",instance!="qnap"} >= 16' }
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
      prometheus+: {
        spec+: {
          // TODO: move ingress and externalURL to an addon
          externalUrl: 'https://prometheus.' + $.values.common.baseDomain,
          retention: '7d',
          retentionSize: '40GB',
          nodeSelector+: {
            'storage.infra/local': 'true',
          },

          podMetadata+: parcaEnable,
          // FIXME: reenable
          securityContext:: null,

          // TODO: expose remoteWrite as a top-level config in kube-prometheus
          remoteWrite: [{
            url: 'http://thanos-receive-router.datalake-metrics.svc:19291/api/v1/receive',
          }],

          // remoteRead: [{
          //   url: "http://mimir.mimir.svc:9009/prometheus/api/v1/read",
          // }],

          enforcedNamespaceLabel: 'namespace',
          excludedFromEnforcement: [
            {
              resource: 'servicemonitors',
              namespace: $.values.common.namespace,
            },
            {
              resource: 'prometheusrules',
              namespace: $.values.common.namespace,
            },
          ],
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
      // FIXME: solve in https://github.com/prometheus-operator/kube-prometheus/issues/1719
      networkPolicy+:: allowIngressNetworkPolicy($.prometheus.service.spec.ports[0].port),
      ingress: ingress(
        $.prometheus.service.metadata {
          name: 'prometheus',  // FIXME: that's an artifact from previous configuration, it should be removed.
        },
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
    },

    kubernetesControlPlane+: {
      // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
      serviceMonitorApiserver:: null,
      serviceMonitorKubeControllerManager:: null,
      serviceMonitorKubeScheduler:: null,
      podMonitorKubeProxy:: null,
      serviceMonitorKubelet+: {
        spec+: {
          endpoints: std.map(
            function(e)
              if !std.objectHas(e, 'path') then
                e {
                  metricRelabelings+: [{
                    sourceLabels: ['url'],
                    targetLabel: 'url',
                    regex: '(.*)\\?.*',
                  }],
                }
              else e,
            super.endpoints,
          ),
          //+ [
          //  // Scrape new /metrics/resource kubelet endpoint. TODO: move to kube-prometheus
          //  {
          //    bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
          //    honorLabels: true,
          //    interval: '30s',
          //    path: '/metrics/resource',
          //    port: 'https-metrics',
          //    relabelings: [{
          //      sourceLabels: ['__metrics_path__'],
          //      targetLabel: 'metrics_path',
          //    }],
          //    scheme: 'https',
          //    tlsConfig: {
          //      insecureSkipVerify: true,
          //    },
          //  },
          //],
        },
      },

      prometheusRule+: {
        spec+: {
          groups: removeAlerts(
            ['KubeMemoryOvercommit', 'KubeCPUOvercommit'],
            'kubernetes-resources',
            super.groups,
          ),
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
      ),
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
              nodeSelector+: {
                'kubernetes.io/arch': 'amd64',
              },
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
              nodeSelector+: {
                'kubernetes.io/arch': 'amd64',
              },
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
          storageClassName: 'qnap-nfs-storage',
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
        $.grafana.service.metadata {
          annotations: {
            'nginx.ingress.kubernetes.io/auth-response-headers': 'X-Auth-Request-Email',
          },
        },
        'grafana.' + $.values.common.baseDomain,
        {
          name: $.grafana.service.metadata.name,
          port: {
            name: $.grafana.service.spec.ports[0].name,
          },
        },
      ),
    },

    //
    // Custom components
    //

    // TODO: Consider moving this out of monitoring NS
    qnap: {
      _metadata:: $.nodeExporter.serviceMonitor.metadata {
        name: 'node-exporter-qnap',
        labels+: {
          'app.kubernetes.io/version':: '',
          'app.kubernetes.io/part-of': 'qnap',
        },
      },
      serviceMonitor: $.nodeExporter.serviceMonitor {
        metadata+: $.qnap._metadata,
        spec+: {
          endpoints: [{
            interval: '15s',
            port: 'http',
            relabelings: [
              {
                action: 'replace',
                regex: '(.*)',
                replacement: '$1',
                sourceLabels: ['__meta_kubernetes_service_label_app_kubernetes_io_part_of'],
                targetLabel: 'instance',
              },
              {
                action: 'replace',
                regex: '(.*)',
                replacement: '$1',
                sourceLabels: ['__meta_kubernetes_endpoints_name'],
                targetLabel: 'pod',
              },
            ],
            metricRelabelings: [{
              action: 'drop',
              regex: 'node_md_disks_required(md9|md13)',
              sourceLabels: ['__name__', 'device'],
            }],
          }],
          selector+: {
            matchLabels+: {
              'app.kubernetes.io/part-of': 'qnap',
            },
          },
        },
      },
      service: $.nodeExporter.service {
        metadata+: $.qnap._metadata,
        spec: {
          clusterIP: 'None',
          ports: [{
            name: 'http',
            port: 9100,
          }],
        },
      },
      endpoints: {
        apiVersion: 'v1',
        kind: 'Endpoints',
        metadata: $.qnap._metadata,
        subsets: [{
          addresses: [{
            ip: '192.168.2.29',
          }],
          ports: [{
            name: 'http',
            port: 9100,
          }],
        }],
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
