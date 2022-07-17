{
  persistentVolume(metadata, capacity, storageClass, nfsServer="none"): {
  ["pv-" + metadata.name]: {
    apiVersion: "v1",
    kind: "PersistentVolume",
    metadata: metadata,
    spec: {
      accessModes: ["ReadWriteOnce"],
      capacity: {
        storage: capacity,
      },
      nfs: {
        path: "/" + metadata.name,
        server: nfsServer,
      },
      persistentVolumeReclaimPolicy: "Retain",
      storageClassName: storageClass,
      volumeMode: "Filesystem",
    },
  },

  ["pvc-" + metadata.name]: {
    apiVersion: "v1",
    kind: "PersistentVolumeClaim",
    metadata: metadata,
    spec: {
      accessModes: ["ReadWriteOnce"],
      resources: {
        requests: {
          storage: capacity
        },
      },
      storageClassName: storageClass,
      volumeName: metadata.name,
    },
  },
},
}