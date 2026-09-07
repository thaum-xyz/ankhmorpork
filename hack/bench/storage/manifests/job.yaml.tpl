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
      # Pinning MUST be nodeAffinity, never nodeName. nodeName bypasses the
      # scheduler, and WaitForFirstConsumer binding depends on the scheduler
      # annotating the PVC with volume.kubernetes.io/selected-node -- with
      # nodeName the annotation is never written, the provisioner never fires,
      # and the PVC sits Pending while the pod sits ContainerCreating forever.
      # Both delayed-binding classes here (lvm-thin, piraeus-r2) hit that.
      #
      # The pin is also what makes per-node numbers comparable: beelink01 runs
      # ubuntu-vg, master02 runs secondary-vg, different physical devices.
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values: ["${NODE}"]
      # Control-plane taints only. Deliberately NOT `operator: Exists`, which
      # would also tolerate node.kubernetes.io/unschedulable and let a heavy IO
      # job land on a node someone cordoned on purpose. Benching master01 means
      # uncordoning it first, as a visible decision.
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
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
            # require-resource-requests ValidatingPolicy wants these set.
            # The CPU limit is sized for master02, which only has 3700m
            # allocatable -- fio must never be the bottleneck, but it also must
            # not get throttled differently per node, so the limit is uniform.
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
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
        - name: scripts
          configMap:
            name: storage-bench-scripts
