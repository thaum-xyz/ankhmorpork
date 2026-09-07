apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: bench
  labels:
    storage-bench/target: ${TARGET_ID}
    storage-bench/class: ${SC}
    storage-bench/node: ${NODE}
spec:
  storageClassName: ${SC}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${VOLUME_SIZE}
