local replaceJobLabel(spec) = {
  indicator+: {
    [if std.objectHas(spec.indicator, 'latency') then 'latency' else 'ratio']+: {
      [if std.objectHas(spec.indicator, 'latency') then 'success' else 'errors']+: {
        metric: std.strReplace(super.metric, 'job="apiserver"', 'component="apiserver"'),
      },
      total+: {
        metric: std.strReplace(super.metric, 'job="apiserver"', 'component="apiserver"'),
      },
    },
  },
};

{
  'slo-apiserver-read-cluster-latency'+: {
    spec+: replaceJobLabel(super.spec),
  },
  'slo-apiserver-read-namespace-latency'+: {
    spec+: replaceJobLabel(super.spec),
  },
  'slo-apiserver-read-resource-latency'+: {
    spec+: replaceJobLabel(super.spec),
  },
  'slo-apiserver-read-response-errors'+: {
    spec+: replaceJobLabel(super.spec),
  },
  'slo-apiserver-write-response-errors'+: {
    spec+: replaceJobLabel(super.spec),
  },
}
