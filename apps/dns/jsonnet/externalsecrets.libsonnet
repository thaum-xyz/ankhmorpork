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
      data: data,
    },
  },
}

//[{
//        secretKey: token
//        remoteRef:
//          key: GITHUB_TOKEN_PROM_STATS
//}],
