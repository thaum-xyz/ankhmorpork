local defaults = {
  local defaults = self,
  name: 'kured',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    //requests: { cpu: '200m', memory: '800Mi' },
    //limits: { cpu: '400m', memory: '1600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'kured',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/part-of': 'kured',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  args: [],
};

function(params) {
  local k = self,
  _config:: defaults + params,
  _metadata:: {
    name: k._config.name,
    namespace: k._config.namespace,
    labels: k._config.commonLabels,
  },
  // Safety check
  //assert std.isObject(k._config.resources),

  // RBAC
  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: k._metadata,
  },

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: k._metadata,
    rules: [
      {
        apiGroups: [''],
        resources: ['nodes'],
        verbs: ['get', 'patch'],
      },
      {
        apiGroups: [''],
        resources: ['pods'],
        verbs: ['list', 'delete', 'get'],
      },
      {
        apiGroups: ['apps'],
        resources: ['daemonsets'],
        verbs: ['get'],
      },
      {
        apiGroups: [''],
        resources: ['pods/eviction'],
        verbs: ['create'],
      },
    ],
  },
  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: k._metadata,
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: k.clusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: k.serviceAccount.metadata.name,
      namespace: k.serviceAccount.metadata.namespace,
    }],
  },
  role: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: k._metadata,
    rules: [{
      apiGroups: ['apps'],
      resources: ['daemonsets'],
      resourceNames: ['kured'],
      verbs: ['update'],
    }],
  },
  roleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: k._metadata,
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: k.role.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: k.serviceAccount.metadata.name,
      namespace: k.serviceAccount.metadata.namespace,
    }],
  },

  // APPLICATION
  daemonSet: {
    local c = {
      name: k._metadata.name,
      image: k._config.image,
      imagePullPolicy: 'IfNotPresent',
      securityContext: {
        privileged: true,  // Give permission to nsenter /proc/1/ns/mnt
      },
      command: ['/usr/bin/kured'],
      args: [
        '--ds-name=' + k.daemonSet.metadata.name,
        '--ds-namespace=' + k._metadata.namespace,
      ] + k._config.args,
      env: [{
        // Pass in the name of the node on which this pod is scheduled
        // for use with drain/uncordon operations and lock acquisition
        name: 'KURED_NODE_ID',
        valueFrom: {
          fieldRef: {
            fieldPath: 'spec.nodeName',
          },
        },
      }],
      ports: [{
        containerPort: 8080,
        name: 'metrics',
      }],
      resources: k._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'DaemonSet',
    metadata: k._metadata {
      annotations: {
        'ignore-check.kube-linter.io/privileged-container': 'kured needs priv container to work',
      },
    },
    spec: {
      selector: {
        matchLabels: k._config.selectorLabels,
      },
      updateStrategy: {
        type: 'RollingUpdate',
      },
      template: {
        metadata: k._metadata,
        spec: {
          serviceAccountName: k.serviceAccount.metadata.name,
          tolerations: [
            {
              key: 'node-role.kubernetes.io/master',
              effect: 'NoSchedule',
            },
            {
              key: 'node-role.kubernetes.io/control-plane',
              operator: 'Exists',
            },
          ],
          hostPID: true,
          restartPolicy: 'Always',
          containers: [c],
        },
      },
    },
  },

  // Monitoring
  podMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PodMonitor',
    metadata: k._metadata,
    spec: {
      podMetricsEndpoints: [{
        port: k.daemonSet.spec.template.spec.containers[0].ports[0].name,
      }],
      selector: {
        matchLabels: k._config.selectorLabels,
      },
    },
  },
}
