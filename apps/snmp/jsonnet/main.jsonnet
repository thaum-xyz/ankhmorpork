local snmp = import 'github.com/thaum-xyz/jsonnet-libs/apps/snmp-exporter/snmp-exporter.libsonnet';
local snmpConfig = importstr '../snmp.yml';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  configData: snmpConfig,
};

local probe(name, namespace, labels, module, targets, interval) = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'Probe',
  metadata: {
    name: name,
    namespace: namespace,
    labels: labels,
  },
  spec: {
    prober: {
      url: 'snmp-exporter.' + namespace + '.svc:9116',
      path: '/snmp',
    },
    module: module,
    targets: {
      staticConfig: {
        labels: {
          module: module,
        },
        static: targets,
      },
    },
    interval: interval,
    scrapeTimeout: interval,
  },
};

local all = snmp(config) + {
  qnapProbe: probe(
    config.targets[0].module,
    config.namespace,
    $.deployment.metadata.labels,
    config.targets[0].module,
    config.targets[0].hosts,
    config.targets[0].interval
  ),
  qnaplongProbe: probe(
    config.targets[1].module,
    config.namespace,
    $.deployment.metadata.labels,
    config.targets[1].module,
    config.targets[1].hosts,
    config.targets[1].interval
  ),
  qnapnewProbe: probe(
    config.targets[2].module,
    config.namespace,
    $.deployment.metadata.labels,
    config.targets[2].module,
    config.targets[2].hosts,
    config.targets[2].interval
  ),
  prometheusRule: {
    apiVersion: "monitoring.coreos.com/v1",
    kind: "PrometheusRule",
    metadata: {
      name: config.name,
      namespace: config.namespace,
      labels: $.deployment.metadata.labels,
    },
    spec: {
      groups: [{
        name: "qnap",
        rules: [
          {
            alert: "QNAPDiskFailure",
            expr: "diskSmartInfo != 0",
            "for": "15m",
            labels: {
              severity: "critical",
            },
            annotations: {
              summary: "QNAP hard drive is faulty",
              description: "SMART data for hard drives number {{ $labels.diskIndex }} on QNAP NAS {{ $labels.instance }} reports disk failure. Disk most probably needs to be replaced as soon as possible.",
              //runbook_url: ""
            },
          },
          {
            alert: "QNAPFirmwareAvailable",
            expr: "firmwareUpgradeAvailable != 0",
            "for": "24h",
            labels: {
              severity: "info",
            },
            annotations: {
              summary: "QNAP NAS firmware upgrade available",
              description: "QNAP NAS {{ $labels.instance }} has pending firmware upgrade.",
              //runbook_url: ""
            },
          },
          {
            alert: "QNAPVolumeNotReady",
            expr: "volumeStatus != 1",
            "for": "10m",
            labels: {
              severity: "warning", // TODO: maybe it should be critical?
            },
            annotations: {
              summary: "QNAP volume is not ready",
              description: "Data Volume number {{ $labels.volumeIndex }} on QNAP {{ $labels.instance }} is not ready.",
              //runbook_url: ""
            },
          },
        ],
      }],
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
