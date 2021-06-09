{
  sealedsecret(name, namespace, encryptedData): {
    apiVersion: "bitnami.com/v1alpha1",
    kind: "SealedSecret",
    metadata: {
      creationTimestamp: null,
      name: name,
      namespace: namespace,
    },
    spec: {
      encryptedData: encryptedData,
      template: {
        metadata: {
          annotations: {
            "sealedsecrets.bitnami.com/managed": "true"
          },
          creationTimestamp: null,
          name: name,
          namespace: namespace,
        }
      }
    }
  },
}
