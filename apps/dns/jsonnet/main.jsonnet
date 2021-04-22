local coredns = import './coredns.libsonnet';
local external = import './externalDNS.libsonnet';

local externaDNSCreds = import '../external-dns-creds.json';
local corefile = importstr '../Corefile';

local all = {
  config:: {
    adblocker: {
      name: 'coredns',
      namespace: 'dns',
      version: '0.2.5',
      image: 'quay.io/paulfantom/coredns-ads:' + self.version,
      loadBalancerIP: '192.168.2.99',
      corefile: corefile,
      commonLabels:: {
        'app.kubernetes.io/name': 'coredns',
        'app.kubernetes.io/version': $.config.adblocker.version,
        'app.kubernetes.io/component': 'adblocker',
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
  adblocker: coredns($.config.adblocker) + {
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
                '192.168.2.1',
                '1.0.0.1',
              ],
            },
          },
        },
      },
    },
  },
};

{ [name + '.yaml']: std.manifestYamlDoc(all.adblocker[name]) for name in std.objectFields(all.adblocker) }
