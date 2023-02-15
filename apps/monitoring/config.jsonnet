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
      requests: { memory: '30Mi' },
    },
    mixin+: {
      _config+: {
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/alertmanager/%s',
      },
    },
  },
  prometheus+: {
    version: '2.42.0',  // application-version-from-github: prometheus/prometheus
    image: 'quay.io/prometheus/prometheus:v2.42.0',  // application-image-from-github: prometheus/prometheus
    externalLabels: {
      cluster: 'ankhmorpork',
    },
    enableFeatures: [
      'memory-snapshot-on-shutdown',
    ],
    resources: {
      requests: { cpu: '140m', memory: '1900Mi' },
      limits: { cpu: '1' },
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
      requests: { cpu: '30m', memory: '16Mi' },
      limits: { cpu: '64m', memory: '42Mi' },
    },
    replicas: 2,
    probes: {
      promDemo: {
        staticConfig: {
          static: [
            'https://demo.do.prometheus.io/',
            'https://prometheus.demo.do.prometheus.io/-/healthy',
            'https://alertmanager.demo.do.prometheus.io/-/healthy',
            'https://node.demo.do.prometheus.io/',
            'https://grafana.demo.do.prometheus.io/api/health',
          ],
          labels: { environment: 'prometheus.io' },
        },
      },
      thaumSites: {
        staticConfig: {
          static: [
            'https://zmc.krupa.net.pl/',
            'https://recipe.krupa.net.pl/api/debug/version',
          ],
          labels: { environment: 'krupa.net.pl' },
        },
      },
      ankhmorpork: {
        staticConfig: {
          static: [
            'https://192.168.2.29/redirect.html',
            //'https://prometheus.ankhmorpork.thaum.xyz/-/healthy',
            //'https://alertmanager.ankhmorpork.thaum.xyz/-/healthy',
            //'https://grafana.ankhmorpork.thaum.xyz/api/health',
          ],
          labels: { environment: 'ankhmorpork' },
          relabelingConfigs: [
            {
              sourceLabels: ['instance'],
              targetLabel: 'instance',
              regex: 'https://192.168.2.29/redirect.html',
              replacement: 'qnap.ankhmorpork.thaum.xyz',
            },
            /*{
              sourceLabels: ['instance'],
              targetLabel: 'instance',
              regex: '$1/-/healthy',
            },
            {
              sourceLabels: ['instance'],
              targetLabel: 'instance',
              regex: '$1/api/health',
            },*/
          ],
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
    mixin+: {
      _config+: {
        diskDeviceSelector: 'device!="md9",device!="md13"',
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/node/%s',
      },
    },
  },
  kubeStateMetrics+: {
    mixin+: {
      _config: {

        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/kube-state-metrics/%s',
      },
    },
  },
  pyrra+: {
    //version: "",
    //image: "",
    //namespace: "monitoring",
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
    version: '0.1.0',  // application-version-from-github: pfnet-research/alertmanager-to-github
    image: 'ghcr.io/pfnet-research/alertmanager-to-github:v0.1.0',  // application-image-from-github: pfnet-research/alertmanager-to-github
    githubTokenSecretName: 'github-receiver-credentials',
    githubTokenRef: 'MONITORING_ALERT_RECEIVER_GITHUB_TOKEN',
  },
  pushgateway: {
    namespace: 'monitoring',
    version: '1.5.1',  // application-version-from-github: prometheus/pushgateway
    image: 'quay.io/prometheus/pushgateway:v1.5.1',  // application-image-from-github: prometheus/pushgateway
    resources: {
      requests: { cpu: '3m', memory: '14Mi' },
      limits: { cpu: '7m', memory: '30Mi' },
    },
  },
  smokeping: {
    name: 'smokeping',
    namespace: 'monitoring',
    version: '0.6.1',  // application-version-from-github: SuperQ/smokeping_prober
    image: 'quay.io/superq/smokeping-prober:v0.6.1',  // application-image-from-github: SuperQ/smokeping_prober
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
    version: 'master',
    image: 'quay.io/prometheuscommunity/json-exporter:master',
    port: 7979,
    resources: {
      requests: { cpu: '3m', memory: '16Mi' },
      limits: { cpu: '20m', memory: '50Mi' },
    },
    targets: ['https://api.uptimerobot.com/v2/getMonitors'],
    credentials: {
      apiKey: 'MONITORING_UPTIMEROBOT_API_KEY',
    },
    config: |||
      headers:
        Content-Type: "application/x-www-form-urlencoded"
        Cache-Control: "no-cache"
      body:
        content: 'api_key={{ .apiKey }}&format=json&response_times=1'
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
