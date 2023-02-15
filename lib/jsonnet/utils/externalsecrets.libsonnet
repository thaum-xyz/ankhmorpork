// 'data' passed in a form of key-value pairs as below:
// {
//  token: GITHUB_TOKEN_PROM_STATS,
//  asfd: asdvbzd,
// },

{
  externalsecret(metadata, store, data): {
    apiVersion: 'external-secrets.io/v1beta1',
    kind: 'ExternalSecret',
    metadata: metadata {
      creationTimestamp: null,
    },
    spec: {
      refreshInterval: '1h',
      secretStoreRef: {
        name: store,
        kind: 'ClusterSecretStore',
      },
      target: {
        name: metadata.name,
      },
      data: std.map(
        function(x)
          {
            secretKey: x,
            remoteRef: {
              key: data[x],
            },
          },
        std.objectFields(data)
      ),
    },
  },
}
