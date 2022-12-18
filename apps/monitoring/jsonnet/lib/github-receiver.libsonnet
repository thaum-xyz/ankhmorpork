local defaults = {
  local defaults = self,
  name: 'github-receiver',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '2m', memory: '10Mi' },
    limits: { cpu: '10m', memory: '50Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'github-receiver',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'alertmanager-webhook-receiver',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  replicas: 1,
  githubTokenSecretName: '',
  titleTemplate: (importstr 'githubReceiver/title-template.tmpl'),
  bodyTemplate: (importstr 'githubReceiver/body-template.tmpl'),
  autoCloseResolvedIssues: false,
  issueLabels: ['alert/new'],
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },
  // Safety check
  assert std.isObject($._config.resources),

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
        port: 8080,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  configs: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: $._metadata {
      name: $._config.name + '-config',
    },
    data: {
      'title-template.txt': $._config.titleTemplate,
      'body-template.txt': $._config.bodyTemplate,
    },
  },

  deployment: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      args: [
              'start',
              '--labels=' + std.join(',', $._config.issueLabels),
              '--auto-close-resolved-issues=' + std.toString($._config.autoCloseResolvedIssues),
            ] + [
              if $._config.titleTemplate != '' then '--title-template-file=/etc/github-receiver/title-template.txt',
            ] +
            [
              if $._config.bodyTemplate != '' then '--body-template-file=/etc/github-receiver/body-template.txt',
            ],
      envFrom: [{
        secretRef: {
          name: $._config.githubTokenSecretName,
        },
      }],
      ports: [{
        containerPort: 8080,
        name: 'http',
      }],
      livenessProbe: {
        httpGet: {
          path: '/metrics',
          port: 8080,
        },
      },
      volumeMounts: [{
        mountPath: '/etc/github-receiver',
        name: 'config',
        readOnly: true,
      }],
      resources: $._config.resources,
    },

    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: $._metadata,
    spec: {
      replicas: $._config.replicas,
      selector: { matchLabels: $._config.selectorLabels },
      template: {
        metadata: {
          annotations: {
            'template.checksum.md5/body': std.md5($._config.bodyTemplate),
            'template.checksum.md5/title': std.md5($._config.titleTemplate),
          },
          labels: $._config.commonLabels,
        },
        spec: {
          containers: [c],
          automountServiceAccountToken: false,
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          nodeSelector: {
            'kubernetes.io/os': 'linux',
            'kubernetes.io/arch': 'amd64',
          },
          volumes: [{
            name: 'config',
            configMap: {
              name: $.configs.metadata.name,
            },
          }],
        },
      },
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: $._metadata,
    spec: {
      endpoints: [{
        port: 'http',
        interval: '30s',
      }],
      selector: {
        matchLabels: $._config.selectorLabels,
      },
    },
  },
}
