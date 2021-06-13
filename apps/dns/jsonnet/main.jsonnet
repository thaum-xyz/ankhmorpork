local coredns = import './coredns.libsonnet';
local external = import './externalDNS.libsonnet';

local externaDNSCreds = import '../external-dns-creds.json';
local corefile = importstr '../Corefile';

local configYAML = (importstr './settings.yaml');

// TODO: figure out how to clean this mess
local all = {
  config:: {
    dnsforwarder: std.parseYaml(configYAML)[0] {
      corefile: corefile,
      commonLabels:: {
        'app.kubernetes.io/name': 'coredns',
        'app.kubernetes.io/version': $.config.dnsforwarder.version,
        'app.kubernetes.io/component': 'dnsforwarder',
      },
      mixin: {
        _config: {
          // TODO: Figure out how to auto-configure this in coredns.libsonnet
          corednsSelector: 'job="coredns"',
        },
        ruleLabels: {
          prometheus: 'k8s',
          role: 'alert-rules',
        },
      },
    },
  },
  dnsforwarder: coredns($.config.dnsforwarder) + {
    local metallbMetadata = {
      metadata+: {
        annotations+: {
          'metallb.universe.tf/address-pool': 'default',
          'metallb.universe.tf/allow-shared-ip': 'dns-svc',
        },
      },
    },
    serviceTCP+: metallbMetadata,
    serviceUDP+: metallbMetadata,
    deployment+: {
      spec+: {
        template+: {
          spec+: {
            dnsConfig+: {
              nameservers: [
                '45.90.28.182',
                '45.90.30.182',
                '192.168.2.1',
              ],
            },
          },
        },
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all.dnsforwarder[name]) for name in std.objectFields(all.dnsforwarder) }
