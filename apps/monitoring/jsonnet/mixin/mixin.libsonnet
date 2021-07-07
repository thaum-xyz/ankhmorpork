{
  prometheusAlerts:: {
    groups: std.parseYaml(importstr 'alerts/testing.yaml').groups + std.parseYaml(importstr 'alerts/thaum.yaml').groups,
  },

}
