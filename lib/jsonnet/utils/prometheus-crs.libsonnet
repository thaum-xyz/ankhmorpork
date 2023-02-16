{
  probe(metadata, prober, module, targets, interval='30s'): {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'Probe',
    metadata: metadata,
    spec: {
      prober: prober,
      module: module,
      targets: targets +
               if std.objectHas(targets, 'staticConfig') then {
                 staticConfig+: {
                   labels+: {
                     module: module,
                   },
                 },
               } else {},
      interval: interval,
      scrapeTimeout: interval,
    },
  },
}
