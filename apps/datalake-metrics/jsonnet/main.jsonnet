local t = import 'kube-thanos/thanos.libsonnet';
local settings = std.parseYaml(importstr '../settings.yaml')[0];

local i = t.receiveIngestor(settings {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
  // Disable shipping to object storage for the purposes of this setup
  objectStorageConfig: null,
  serviceMonitor: true,
});

local r = t.receiveRouter(settings {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
  // Disable shipping to object storage for the purposes of this setup
  objectStorageConfig: null,
  endpoints: i.endpoints,
});

local s = t.store(settings {
  replicas: 1,
  serviceMonitor: true,
});

local q = t.query(settings {
  replicas: 1,
  replicaLabels: ['prometheus_replica', 'rule_replica'],
  serviceMonitor: true,
  stores: [s.storeEndpoint] + i.storeEndpoints,
});

local all = {
  query: q,
  store: s,
  receiveRouter: r,
  receiveIngestor: {
    [resource]: i[resource]
    for resource in std.objectFields(i)
    if resource != 'ingestors'
  } + {
    ['ingestor-' + hashring + '-' + resource]: i.ingestors[hashring][resource]
    for hashring in std.objectFields(i.ingestors)
    for resource in std.objectFields(i.ingestors[hashring])
    if i.ingestors[hashring][resource] != null
  },
};

// Manifestation
{
  [component + '/' + resource + '.yaml']: std.manifestYamlDoc(all[component][resource])
  for component in std.objectFields(all)
  for resource in std.objectFields(all[component])
}
