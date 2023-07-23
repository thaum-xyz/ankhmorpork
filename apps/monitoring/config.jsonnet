// TODO: convert file to yaml and figure out how to merge configuration as `std.mergePatch` may not be enough

{
  common+: {
    namespace: 'monitoring',
    ruleLabels: {
      role: 'alert-rules',
    },
    baseDomain: 'ankhmorpork.thaum.xyz',
  },
  windowsExporter: {
    namespace: 'monitoring',
    nodes: [
      '192.168.2.50',
      '192.168.2.51',
    ],
  },
  alertmanager+: {
    resources+: {
      requests: {
        cpu: '3m',
        memory: '30Mi',
      },
    },
    mixin+: {
      _config+: {
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/alertmanager/%s',
      },
    },
    credentialsRefs: {
      healthchecks_url: 'MONITORING_AM_HEALTHCHECKS_URL',
      opsgenie_api_key: 'MONITORING_AM_OPSGENIE_API_KEY',
      slack_api_url: 'MONITORING_AM_SLACK_API_URL',
    },
  },
  prometheus+: {
    version: '2.45.0',  // application-version-from-github: prometheus/prometheus
    image: 'quay.io/prometheus/prometheus:v2.45.0',  // application-image-from-github: prometheus/prometheus
    externalLabels: {
      cluster: 'ankhmorpork',
    },
    enableFeatures: [
      'memory-snapshot-on-shutdown',
    ],
    resources: {
      requests: { cpu: '500m', memory: '1800Mi' },
      limits: { cpu: '1500m', memory: '4Gi' },
    },
    affinity: {
      nodeAffinity: {
        preferredDuringSchedulingIgnoredDuringExecution: [{
          weight: 1,
          preference: {
            matchExpressions: [{
              key: 'kubernetes.io/arch',
              operator: 'In',
              values: ['amd64'],
            }],
          },
        }],
      },
    },
    mixin+: {
      _config: {
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/prometheus/%s',
      },
    },
  },
  prometheusOperator+: {
    // version: '0.52.0',
    // image: 'quay.io/prometheus-operator/prometheus-operator:v0.52.0',
    // configReloaderImage: 'quay.io/prometheus-operator/prometheus-config-reloader:v0.52.0',
    extraArgs:: [
      '--log-level=debug',
      '--config-reloader-cpu-request=2m',
      '--config-reloader-memory-request=17Mi',
    ],
    resources: {
      requests: { cpu: '5m', memory: '34Mi' },
    },
    mixin+: {
      _config: {
        prometheusOperatorSelector: 'job="prometheus-operator"',
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/prometheus-operator/%s',
      },
    },
  },
  blackboxExporter+: {
    // Using only HTTP module
    modules: {
      http_2xx: {
        http: {
          preferred_ip_protocol: 'ip4',
        },
        prober: 'http',
      },
    },
    resources: {
      requests: { cpu: '30m', memory: '20Mi' },
      limits: { cpu: '200m', memory: '42Mi' },
    },
    replicas: 2,
    probes: {
      thaumSites: {
        staticConfig: {
          static: [
            'https://zmc.krupa.net.pl/',
          ],
          labels: { environment: 'lancre' },
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
          relabelingConfigs: [
            {
              // Care only about / path exposed by ingress
              // FIXME: this should be changed to care either about / or path specified in probe-uri annotation
              sourceLabels: ['__meta_kubernetes_ingress_path'],
              regex: '/',
              action: 'keep',
            },
          ],
        },
      },
    },
  },
  kubernetesControlPlane+: {
    kubeProxy: true,
    mixin+: {
      _config+: {
        // k3s exposes all this data under single endpoint and those can be obtained via "kubelet" Service
        kubeSchedulerSelector: 'job="kubelet"',
        kubeControllerManagerSelector: 'job="kubelet"',
        kubeApiserverSelector: 'job="kubelet"',
        kubeProxySelector: 'job="kubelet"',
        //windowsExporterSelector: 'job="windows-exporter"',  # FIXME: this is set in lib/windows-exporter.libsonnet
        cpuThrottlingPercent: 70,
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/kubernetes/%s',
      },
    },
  },
  nodeExporter+: {
    version: '1.4.0',
    image: 'quay.io/prometheus/node-exporter:v1.4.0',
    filesystemMountPointsExclude:: '^/(dev|proc|sys|run/k3s/containerd/.+|var/lib/docker/.+|var/lib/kubelet/pods/.+)($|/)',
    resources:: {
      requests: { cpu: '2m', memory: '20Mi' },
      limits: { cpu: '150m', memory: '180Mi' },
    },
    kubeRbacProxy:: {
      resources+: {
        requests: { cpu: '1m', memory: '16Mi' },
      },
    },
    mixin+: {
      _config+: {
        diskDeviceSelector: 'device!="md9",device!="md13"',
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/node/%s',
      },
    },
  },
  kubeStateMetrics+: {
    resources:: {
      requests: { cpu: '2m', memory: '34Mi' },
      limits: { cpu: '200m', memory: '180Mi' },
    },
    kubeRbacProxyMain+:: {
      resources+: {
        requests: { cpu: '2m', memory: '14Mi' },
        limits+: { cpu: '40m' },
      },
    },
    kubeRbacProxySelf+:: {
      resources+: {
        requests: { cpu: '1m', memory: '14Mi' },
        limits+: { cpu: '40m' },
      },
    },
    mixin+: {
      _config: {
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/kube-state-metrics/%s',
      },
    },
  },
  pyrra+: {
    version: '0.6.3',
    image: 'ghcr.io/pyrra-dev/pyrra:v0.6.3',
    namespace: 'monitoring',
    resources: {
      requests: { cpu: '100m', memory: '30Mi' },
      //limits: { cpu: '100m', memory: '30Mi' },
    },
  },
  grafana+: {
    version: '9.1.7',
    image: 'grafana/grafana:9.1.7',
    datasources: [{
      name: 'Prometheus',
      type: 'prometheus',
      access: 'proxy',
      orgId: 1,
      isDefault: true,
      url: 'http://prometheus-k8s.monitoring.svc:9090',
    }],
    resources+: {
      requests+: {
        memory: '59Mi',
      },
      limits+: {
        cpu: '400m',
      },
    },
    // TODO: Consider moving those into `grafana.config`
    env: [
      { name: 'GF_SERVER_ROOT_URL', value: 'https://grafana.ankhmorpork.thaum.xyz' },
      { name: 'GF_AUTH_ANONYMOUS_ENABLED', value: 'false' },
      { name: 'GF_AUTH_DISABLE_LOGIN_FORM', value: 'true' },
      { name: 'GF_AUTH_SIGNOUT_REDIRECT_URL', value: 'https://auth.ankhmorpork.thaum.xyz/oauth2?logout=true' },
      { name: 'GF_AUTH_BASIC_ENABLED', value: 'false' },
      { name: 'GF_AUTH_PROXY_AUTO_SIGN_UP', value: 'false' },
      { name: 'GF_AUTH_PROXY_ENABLED', value: 'true' },
      { name: 'GF_AUTH_PROXY_HEADER_NAME', value: 'X-Auth-Request-Email' },
      { name: 'GF_AUTH_PROXY_HEADER_PROPERTY', value: 'username' },
      { name: 'GF_AUTH_PROXY_HEADERS', value: 'Email:X-Auth-Request-Email' },
      { name: 'GF_SNAPSHOTS_EXTERNAL_ENABLED', value: 'false' },
    ],
  },
  // Following are not in kube-prometheus
  githubReceiver: {
    namespace: 'monitoring',
    version: '0.1.1',  // application-version-from-github: pfnet-research/alertmanager-to-github
    image: 'ghcr.io/pfnet-research/alertmanager-to-github:v0.1.1',  // application-image-from-github: pfnet-research/alertmanager-to-github
    githubTokenSecretName: 'github-receiver-credentials',
    githubTokenRef: 'MONITORING_ALERT_RECEIVER_GITHUB_TOKEN',
    resources+: {
      requests: { cpu: '2m', memory: '23Mi' },
    },
  },
  pushgateway: {
    namespace: 'monitoring',
    version: '1.6.0',  // application-version-from-github: prometheus/pushgateway
    image: 'quay.io/prometheus/pushgateway:v1.6.0',  // application-image-from-github: prometheus/pushgateway
    resources: {
      requests: { cpu: '3m', memory: '25Mi' },
      limits: { cpu: '10m', memory: '40Mi' },
    },
  },
  smokeping: {
    name: 'smokeping',
    namespace: 'monitoring',
    version: '0.7.1',  // application-version-from-github: SuperQ/smokeping_prober
    image: 'quay.io/superq/smokeping-prober:v0.7.1',  // application-image-from-github: SuperQ/smokeping_prober
    port: 9374,
    resources: {
      requests: { cpu: '40m', memory: '30Mi' },
      limits: { memory: '70Mi' },
    },
    replicas: 2,
    args: [
      '8.8.8.8',
      '1.1.1.1',
      'lancre.thaum.xyz',
      'krupa.net.pl',
      'pawel.krupa.net.pl',
    ],
  },
  uptimerobot: {
    name: 'uptimerobot',
    namespace: 'monitoring',
    version: '0.5.0',
    image: 'quay.io/prometheuscommunity/json-exporter:v0.5.0',
    port: 7979,
    resources: {
      requests: { cpu: '5m', memory: '18Mi' },
      limits: { cpu: '20m', memory: '50Mi' },
    },
    targets: ['https://api.uptimerobot.com/v2/getMonitors'],
    credentials: {
      apiKeyRef: 'MONITORING_UPTIMEROBOT_API_KEY',
    },
    config: |||
      modules:
        default:
          headers:
            Content-Type: "application/x-www-form-urlencoded"
            Cache-Control: "no-cache"
          body:
            content: 'api_key={{ .apiKeyRef }}&format=json&response_times=1'
          metrics:
          - name: "uptimerobot_monitor"
            type: "object"
            # Filter out components without a name
            path: '{.monitors[?(@.friendly_name != "")]}'
            help: "Information about uptimerobot monitor"
            labels:
              monitor: '{.friendly_name}'
              url: '{.url}'
            values:
              status: '{.status}'
              response_time_miliseconds: '{.average_response_time}'
    |||,
  },

  other: {},
}
