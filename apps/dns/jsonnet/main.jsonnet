local sealedsecret = (import '../../../lib/sealedsecret.libsonnet').sealedsecret;
local coredns = import './coredns.libsonnet';
local external = import './externalDNS.libsonnet';

local externaDNSCreds = import '../external-dns-creds.json';
local corefile = importstr '../Corefile';

local configYAML = (importstr './settings.yaml');

// TODO: figure out how to clean this mess
local all = {
  config:: {
    coredns: std.parseYaml(configYAML)[0] {
      corefile: corefile,
      secretName: 'coredns-envs',
      mixin: {
        _config: {
          // TODO: Figure out how to auto-configure this in coredns.libsonnet
          corednsSelector: 'job=~"kube-dns|coredns"',
          dashboardTags: ['coredns', 'mixin'],
        },
        ruleLabels: {
          prometheus: 'k8s',
          role: 'alert-rules',
        },
      },
    },
  },
  coredns: coredns($.config.coredns) + {
    envs: sealedsecret(
      $.coredns.serviceAccount.metadata { name: $.config.coredns.secretName },
      {
        NEXTDNS_ID: $.config.coredns.nextDNSID,
      }
    ),
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

{ [name + '.yaml']: std.manifestYamlDoc(all.coredns[name]) for name in std.objectFields(all.coredns) }
