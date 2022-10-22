local defaults = {
  local defaults = self,
  name: 'api',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  //credentialsSecretRef: error 'must provide credentials Secret name',
  image: error 'must provide api image',
  resources: {
    //requests: { cpu: '90m', memory: '150Mi' },
    //limits: { cpu: '200m', memory: '300Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'api',
    'app.kubernetes.io/part-of': 'mealie',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  storage: {
    name: defaults.name,
    pvcSpec: {
      accessModes: ['ReadWriteMany'],
      resources: {
        requests: {
          storage: '1Gi',
        },
      },
    },
  },
};

function(params) {
  local m = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject($._config.resources),

  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  // TODO: figure out where to put this as it is also needed in API
  pvc: {
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: m._metadata {
      name: $._config.storage.name,
    },
    spec: $._config.storage.pvcSpec,
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: $._metadata,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: $.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 9000,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  deployment: {
    local c = {
      name: $._metadata.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      env: [
        {
          name: 'ALLOW_SIGNUP',
          value: 'false',
        },
        {
          name: 'DB_ENGINE',
          value: 'sqlite',
        },
      ],
      /*envFrom: [{
        secretRef: {
          name: $._config.credentialsSecretRef,
        },
      }],*/
      ports: [{
        containerPort: 9000,
        name: 'http',
      }],
      /*readinessProbe: {
        httpGet: {
          path: '/api/debug/version',
          port: 'http',
          scheme: 'HTTP',
        },
        initialDelaySeconds: 5,
        failureThreshold: 5,
        timeoutSeconds: 10,
      },*/
      volumeMounts: [{
        mountPath: '/app/data',
        name: 'appdata',
      }],
      resources: $._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: 1,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          labels: $._config.commonLabels,
        },
        spec: {
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          volumes: [{
            name: 'appdata',
            persistentVolumeClaim: {
              claimName: $.pvc.metadata.name,
            },
          }],
        },
      },
    },
  },

}
