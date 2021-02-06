{
    // This addon will configure additionalScrapeConfigs in main prometheus
    // It will also load scrape configs from additional-scrape-configs.yaml file
    // and wrap it into a correct secret.
    prometheus+: {
        local p = self,
      prometheus+: {
          additionalScrapeConfigs: {
              name: 'additional-scrape-config',
              key: 'additional-scrape-configs.yaml',
          },
      },
      additionalScrapeConfig: {
        apiVersion: 'v1',
        kind: 'Secret',
        metadata: {
            name: 'additional-scrape-config',
            namespace: p.config.namespace,
            labels: { prometheus: p.config.name } + p.config.commonLabels,
        },
        stringData: {
            'additional-scrape-configs.yaml': importstr 'additional-scrape-configs.yaml',
        },
      },
    },
}