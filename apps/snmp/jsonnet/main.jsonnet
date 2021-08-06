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
  )
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
