// convert file to yaml when jsonnet supports yaml imports (https://github.com/google/jsonnet/pull/888)
local blackboxExporterModules = (import 'ext/blackboxExporterConfig.json').modules;

{
  common+: {
    namespace: 'monitoring',
    ruleLabels: {
      role: 'alert-rules',
    },
    baseDomain: 'ankhmorpork.thaum.xyz',
  },
  alertmanager+: {
    resources: {
      requests: { memory: '30Mi' },
    },
  },
  prometheus+: {
    version: '2.26.0',
    image: 'quay.io/prometheus/prometheus:v2.26.0',
    ruleSelector: {},
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
  // Following are not in kube-prometheus
  kubeEventsExporter: {
    namespace: 'monitoring',
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
    namespace: 'monitoring',
    version: '1.2.0',
    image: 'quay.io/prometheus/pushgateway:v1.2.0',
    resources: {
      requests: { cpu: '10m', memory: '12Mi' },
    },
  },
  smokeping: {
    name: 'smokeping',
    namespace: 'monitoring',
    version: '0.4.2',
    image: 'quay.io/superq/smokeping-prober:v0.4.2',
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
  uptimerobot: {
    name: 'uptimerobot-exporter',
    namespace: 'monitoring',
    version: 'latest',
    image: 'drubin/uptimerobot-prometheus-exporter',
    resources: {
      requests: { cpu: '10m', memory: '13Mi' },
      limits: { memory: '30Mi' },
    },
    port: 9429,
    secretRefName: 'uptimerobot-api-key',
  },
}
