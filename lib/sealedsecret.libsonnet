{
  sealedsecret(metadata, encryptedData): {
    apiVersion: "bitnami.com/v1alpha1",
    kind: "SealedSecret",
    metadata: metadata {
      creationTimestamp: null,
    },
    spec: {
      encryptedData: encryptedData,
      template: {
        metadata: metadata {
          annotations: {
            "sealedsecrets.bitnami.com/managed": "true"
          },
          creationTimestamp: null,
        }
      }
    }
  },
}
