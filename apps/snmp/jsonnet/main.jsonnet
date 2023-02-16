local snmp = import 'github.com/thaum-xyz/jsonnet-libs/apps/snmp-exporter/snmp-exporter.libsonnet';
local probe = (import '../../../lib/jsonnet/utils/prometheus-crs.libsonnet').probe;
local snmpConfig = importstr '../snmp.yml';

local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  configData: snmpConfig,
};

local all = snmp(config) + {
  deployment+: {
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            'parca.dev/scrape': 'true',
          },
        },
      },
    },
  },
  local probeMetadata = {
    namespace: config.namespace,
    labels: $.deployment.metadata.labels,
  },
  local prober = {
    url: 'snmp-exporter.' + config.namespace + '.svc:9116',
    path: '/snmp',
  },

  qnapProbe: probe(
    probeMetadata { name: config.targets[0].module },
    prober,
    config.targets[0].module,
    config.targets[0].config,
    config.targets[0].interval
  ),
  qnaplongProbe: probe(
    probeMetadata { name: config.targets[1].module },
    prober,
    config.targets[1].module,
    config.targets[1].config,
    config.targets[1].interval
  ),
  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      name: config.name,
      namespace: config.namespace,
      labels: $.deployment.metadata.labels,
    },
    spec: {
      groups: [{
        name: 'qnap',
        rules: [
          {
            alert: 'QNAPDiskFailure',
            expr: 'diskSmartInfo != 0',
            'for': '15m',
            labels: {
              severity: 'critical',
            },
            annotations: {
              summary: 'QNAP hard drive is faulty',
              description: 'SMART data for hard drives number {{ $labels.diskIndex }} on QNAP NAS {{ $labels.instance }} reports disk failure. Disk most probably needs to be replaced as soon as possible.',
              //runbook_url: ""
            },
          },
          {
            alert: 'QNAPFirmwareAvailable',
            expr: 'firmwareUpgradeAvailable != 0',
            'for': '24h',
            labels: {
              severity: 'info',
            },
            annotations: {
              summary: 'QNAP NAS firmware upgrade available',
              description: 'QNAP NAS {{ $labels.instance }} has pending firmware upgrade.',
              //runbook_url: ""
            },
          },
          {
            alert: 'QNAPVolumeNotReady',
            expr: 'volumeStatus != 0',
            'for': '2h',
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'QNAP volume is not ready',
              description: 'Data Volume number {{ $labels.volumeIndex }} on QNAP {{ $labels.instance }} is not ready for last 2h.',
              //runbook_url: ""
            },
          },
          {
            alert: 'QNAPVolumeNotReady',
            expr: 'volumeStatus < 0',
            'for': '10m',
            labels: {
              severity: 'critical',
            },
            annotations: {
              summary: 'QNAP volume is in critical state',
              description: 'Data Volume number {{ $labels.volumeIndex }} on QNAP {{ $labels.instance }} is in critical state and needs immediate attention.',
              //runbook_url: ""
            },
          },
          {
            alert: 'QNAPRAIDProblem',
            expr: 'raidStatus < 0',
            'for': '20m',
            labels: {
              severity: 'critical',
            },
            annotations: {
              summary: 'QNAP RAID is in error state',
              description: 'RAID array number {{ $labels.raidIndex }} on QNAP {{ $labels.instance }} is in critical state and needs immediate attention.',
              //runbook_url: ""
            },
          },
          {
            alert: 'QNAPRAIDProblem',
            expr: 'raidStatus != 0',
            'for': '12h',
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'QNAP RAID is in warning state',
              description: 'RAID array number {{ $labels.raidIndex }} on QNAP {{ $labels.instance }} is in warning state for last 12h.',
              //runbook_url: ""
            },
          },
          {
            alert: 'QNAPWriteCacheUnused',
            expr: 'max_over_time(cacheWriteHitRate[24h]) == 0 AND cacheAccelerationServiceEnabled == 1',
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'QNAP Write Cache has 0% hit rate.',
              description: "Write cache on QNAP {{ $labels.instance }} has 0% hit rate and is most likely unusued. Consider checking if cache setup didn't switch to read-only mode.",
              //runbook_url: ""
            },
          },
        ],
      }],
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
