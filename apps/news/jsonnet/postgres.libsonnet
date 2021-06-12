local defaults = {
  local defaults = self,
  name: 'postgres',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    //requests: { cpu: '200m', memory: '800Mi' },
    //limits: { cpu: '400m', memory: '1600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'postgres',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'database',
    'app.kubernetes.io/part-of': 'postgres',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  configEnvs: {},
  pvcSpec: '',
};

function(params) {
  local p = self,
  _config:: defaults + params,
  _metadata:: {
    name: p._config.name,
    namespace: p._config.namespace,
    labels: p._config.commonLabels,
  },
  // Safety check
  // assert std.isObject(p._config.resources),
  //assert std.objectHas(p._config.configEnvs, 'POSTGRES_DB'),
  //assert std.objectHas(p._config.configEnvs, 'POSTGRES_USER'),
  //assert std.objectHas(p._config.configEnvs, 'POSTGRES_PASSWORD'),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: p._metadata,
  },

  secret: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: p._metadata,
    data: p._config.configEnvs,
    // POSTGRES_DB
    // POSTGRES_USER
    // POSTGRES_PASSWORD
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: p._metadata,
    spec: {
      ports: [{
        name: 'tcp',
        targetPort: p.statefulSet.spec.template.spec.containers[0].ports[0].name,
        port: 5432,
      }],
      selector: p._config.selectorLabels,
    },
  },

  statefulSet: {
    local c = {
      name: p._config.name,
      image: p._config.image,
      imagePullPolicy: 'IfNotPresent',
      envFrom: [{
        secretRef: {
          name: p.secret.metadata.name,
        },
      }],
      ports: [{
        containerPort: 5432,
        name: 'tcp',
      }],
      readinessProbe: {
        exec: {
          // Needs bash for env variable extrapolation - https://github.com/kubernetes/kubernetes/issues/40846
          command: ['bash', '-c', 'pg_isready -U $POSTGRES_USER'],
        },
        initialDelaySeconds: 15,
        timeoutSeconds: 2,
      },
      volumeMounts: [{
        mountPath: '/var/lib/postgresql/data',
        name: 'data',
      }],
      resources: p._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: p._metadata,
    spec: {
      serviceName: p.service.metadata.name,
      replicas: 1,
      selector: { matchLabels: p._config.selectorLabels },
      template: {
        metadata: {
          labels: p._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: p.serviceAccount.metadata.name,
          volumes: [{
            name: 'data',
            // Add conditional based on pvcSpec
            persistentVolumeClaim: {
              claimName: p.pvc.metadata.name,
            },
          }],
        },
      },
    },
  },

  pvc: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: p._metadata,
    spec: p._config.pvcSpec,
  },
}
