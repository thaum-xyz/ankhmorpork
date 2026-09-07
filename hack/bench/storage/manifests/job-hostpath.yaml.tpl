apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: bench
  labels:
    storage-bench/target: ${TARGET_ID}
    storage-bench/class: ${SC}
    storage-bench/node: ${NODE}
spec:
  backoffLimit: 0
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        storage-bench/target: ${TARGET_ID}
    spec:
      restartPolicy: Never
      # No PVC and no CSI driver: this target writes straight onto the
      # filesystem Longhorn keeps its sparse replica files on, to establish what
      # that device costs before any Longhorn code touches it.
      #
      # The scratch directory sits beside `replicas/`, not inside it, so nothing
      # here looks like a replica to Longhorn. The file is removed by the
      # entrypoint when fio finishes.
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values: ["${NODE}"]
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: fio
          image: ${FIO_IMAGE}
          command: ["/bin/sh", "/scripts/entrypoint.sh"]
          env:
            - name: MOUNT
              value: /data
            - name: FIO_SIZE
              value: "${FIO_SIZE}"
            - name: FIO_DIRECT
              value: "${FIO_DIRECT}"
            - name: FIO_OFFSET_INCREMENT
              value: "${FIO_OFFSET_INCREMENT}"
            - name: RUNTIME
              value: "${RUNTIME}"
            - name: PROFILE
              value: "${PROFILE}"
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
            limits:
              cpu: "3"
              memory: 1Gi
          volumeMounts:
            - name: data
              mountPath: /data
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: data
          hostPath:
            path: ${HOSTPATH}
            type: DirectoryOrCreate
        - name: scripts
          configMap:
            name: storage-bench-scripts
