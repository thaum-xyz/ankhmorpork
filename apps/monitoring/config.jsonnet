// TODO: convert file to yaml and figure out how to merge configuration as `std.mergePatch` may not be enough

{
  common+: {
    namespace: 'monitoring',
    ruleLabels: {
      role: 'alert-rules',
    },
    baseDomain: 'ankhmorpork.thaum.xyz',
  },
  windowsScrapeConfig+: {
    job_name: 'windows',
    static_configs: [{
      targets: [
        '192.168.2.50:9182',
        '192.168.2.51:9182',
      ],
    }],
    metric_relabel_configs: [
      {
        action: 'replace',
        replacement: 'pawelpc',
        regex: '192.168.2.50:9182',
        source_labels: ['instance'],
        target_label: 'node',
      },
      {
        action: 'replace',
        replacement: 'aduspc',
        regex: '192.168.2.51:9182',
        source_labels: ['instance'],
        target_label: 'node',
      },
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
    version: '2.30.3',  // application-version-from-github: prometheus/prometheus
    image: 'quay.io/prometheus/prometheus:v2.30.3',  // application-image-from-github: prometheus/prometheus
    externalLabels: {
      cluster: 'ankhmorpork',
    },
    enableFeatures: ['remote-write-receiver'],
    resources: {
      requests: { cpu: '140m', memory: '1900Mi' },
      limits: { cpu: '1' },
    },
    mixin+: {
      _config: {
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/prometheus/%s',
      },
    },
    // More in https://kubernetes.github.io/ingress-nginx/examples/auth/basic/
    // Password stored in bitwarden
    remoteWriteAuth: 'AgDGeT9BN6FzkFxAGIEfp/DSRL+jQ+CFoLiwAXUWC6QtfDFgWyQGauDRQqWvsPCWrCFNNSi0qsb8ObppQpVAftJLXZL+HI44me3AviYfMUPif7r5XKvcjhMkR+X7Cpk3/67ewlPDO5kHMuVosyVVbtGF4uznwPsi1mH+pRHsdSo76muFNNY/Cvr5stEtk+6UYakFZvti0Pe24nOI+mf0weBRLkyo45uZWOG4Lgok4AO84h9lKEJb6ROWYHs5neJua6JevdtQSOUo5xKyBCHNpkCrtkn0QkX6pSwwTL90s7em1anJL5pXy/oHSfaqa2VkQ6pDvgFylrXAr049sen8v5zaQoemQ9m3jKD8b5sZbBRhV5AxEGd8AH4f0S33zeVmwNyc0DiSE7riFPPTxvXPmW0JVubYSj7rr1aANNKW8UVzTRNutsX/SyxN8FgLPb41miuNVN0GOH8qA58l3t4LxaoDeAeLfg8VgOZ6yf2g1yhEzpSG98VIvt5hDxwlQvOlpUqXjckuV+bWDhiQYUQZFmzLWNJ/ki7E9mGM8kJ0nIQHiB3zg1cfEIoeSB0930upjll48/r57+m/TSjrymVgMzGwzJ/dd7tjeBagpVBsxnPdLY4PTKA6g5SJsDTDLzdWKsjHhoQR62WIUhC8QV8m8m9xYSAyfnaNVUVwh5b2q+5Q3agilaquFO3Ay1AZbS0x4n3K6WkJQHF2h1qR97PmW5YFrDH3gg6YzNyEDDEUQlNv6KL0D+NUzXXotxMH67A3',
  },
  prometheusOperator+: {
    version: '0.51.1',
    # image: 'quay.io/prometheus-operator/prometheus-operator:v0.51.1',
    image: 'quay.io/paulfantom/prometheus-operator-dev:v0.51.2-97d7df9eb',
    configReloaderImage: 'quay.io/prometheus-operator/prometheus-config-reloader:v0.51.1',
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
          ],
          labels: { environment: 'lancre.thaum.xyz' },
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
        cpuThrottlingPercent: 70,
        runbookURLPattern: 'https://runbooks.thaum.xyz/runbooks/kubernetes/%s',
      },
    },
  },
  nodeExporter+: {
    mixin+: {
      _config: {
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
  grafana+: {
    version: '8.2.1',
    image: 'grafana/grafana:8.2.1',
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
  kubeEventsExporter: {
    namespace: 'monitoring',
    version: '0.1.0',  // application-version-from-github: rhobs/kube-events-exporter
    image: 'quay.io/dgrisonnet/kube-events-exporter:v0.1.0',  // application-image-from-github: rhobs/kube-events-exporter
    resources: {
      requests: { cpu: '2m', memory: '11Mi' },
      limits: { cpu: '5m', memory: '30Mi' },
    },
    commonLabels+: {
      'app.kubernetes.io/component': 'exporter',
    },
  },
  pushgateway: {
    namespace: 'monitoring',
    version: '1.4.2',  // application-version-from-github: prometheus/pushgateway
    image: 'quay.io/prometheus/pushgateway:v1.4.2',  // application-image-from-github: prometheus/pushgateway
    resources: {
      requests: { cpu: '3m', memory: '14Mi' },
      limits: { cpu: '7m', memory: '30Mi' },
    },
  },
  smokeping: {
    name: 'smokeping',
    namespace: 'monitoring',
    version: '0.4.2',  // application-version-from-github: SuperQ/smokeping_prober
    image: 'quay.io/superq/smokeping-prober:v0.4.2',  // application-image-from-github: SuperQ/smokeping_prober
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
      'cloud.krupa.net.pl',
      'pawel.krupa.net.pl',
    ],
  },
  pagespeed: {
    name: 'pagespeed',
    namespace: 'monitoring',
    version: 'latest',
    image: 'foomo/pagespeed_exporter',
    resources: {
      requests: { cpu: '10m', memory: '13Mi' },
      limits: { memory: '30Mi' },
    },
    sites: [
      'https://prometheus.io',
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
    args: [
      '--config.file',
      '/etc/json_exporter/config.yml',
    ],
    credentials: {
      API_KEY: 'AgDBgACduTClD7MpWPxletQQpxZRPDNrEHjtH5Ssn4IYh/ZVkFaNDcAjcISKRwgvwGZ8zkVsBGo3jfeGo47Tu+6uiHaWTtCKHn4wKmWDykaEHN/rGo+uP9qzbppoyosiAsalitdHzPacZ/IqgEiVLLJLf9S/Y4FcTcgOeeB1WUBQ8PyS5UhbNRyVkt3i9CG5u6WMKh+q8pioULec0C3KIkhSDorKRzcwr1Y446h9RCU57jVCbBr2hqQ68NNFqX37r2lnX+T6fNbkLploG2tkpg1CCYLzHJLGvYSHyP6EGjVBux/t4bOSP4bn8v+vNByBkhxxdiiyKTlmZq5E98bVIWaBMbis1i01u9/0snsTxAr3cXoRjCL/s+Kq6Mf+Fax9BZh+7okhJ8/Uz+1ReNsolV4u/xJnOeVxf4PUiL/1eLkNfxqUQbD8xsz9QR41N+hvpu4QkuaRv0BbEIt794X/nGpb+AJgFs8Xh+R+SNbqcqpLXg6yokETvZLszXZiRaheyhqPZB8j89p8QOiQYVeKQFhNjtknSXihdUXHs1z441ysDvjeap1DrXEHYUDgHFhQPF8sziyrVODwaQR65Iym0BC9cvfDM44q/cxGt2JtGeMp+6Oqw5ikGZOqVw9NmK1/GRMuTfAsHUrGZ0g2vyPYJUEo0qc5Ig28MfGPUi1q/bBgRc73ALIxNWGcN1137eTh5yQbA1/GlFaWYdT2eIJ+aPpxg6bbIsG+B2bxE1qiD5cRoTc1',
    },
    config: |||
      headers:
        Content-Type: "application/x-www-form-urlencoded"
        Cache-Control: "no-cache"
      body:
        content: 'api_key={{ index . "API_KEY" }}&format=json&response_times=1'
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
