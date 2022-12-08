{
  prometheusAlerts:: {
    groups:
      std.parseYaml(importstr 'testing.yaml').groups +
      // std.parseYaml(importstr 'thaum.yaml').groups +
      std.parseYaml(importstr 'openshift.yaml').groups +
      [],
  },
}
