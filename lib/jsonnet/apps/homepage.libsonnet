local affinity = (import 'utils/pod.libsonnet').antiaffinity;

local defaults = {
  local defaults = self,
  name: 'homepage',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '1m', memory: '5Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'homepage',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'server',
    'app.kubernetes.io/part-of': 'homepage',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  replicas: 1,
  ingress: {
    domain: '',
    className: 'nginx',
    annotations: {
      'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
    },
  },
  configData: error 'must provide configData',
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

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: $._metadata,
    rules: [
      {
        apiGroups: [""],
        resources: ["namespaces", "pods", "nodes"],
        verbs: ["get", "list"],
      },{
        //apiGroups: ["extensions","networking.k8s.io",],
        apiGroups: ["networking.k8s.io"],
        resources: ["ingresses"],
        verbs: ["get", "list"],
      }, {
        apiGroups: ["metrics.k8s.io"],
        resources: ["nodes", "pods"],
        verbs: ["get", "list"],
      },
    ],
  },

  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: $._metadata,
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: $.clusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: $.serviceAccount.metadata.name,
      namespace: $.serviceAccount.metadata.namespace,
    }],
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: $._metadata,
    spec: {
      ports: [{
        name: 'http',
        targetPort: $.deployment.spec.template.spec.containers[0].ports[0].name,
        port: 3000,
      }],
      selector: $._config.selectorLabels,
      clusterIP: 'None',
    },
  },

  configmap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: $._metadata {
      name: $._config.name + '-config',
    },
    data: $._config.configData,
  },

  deployment: {
    local c = {
      name: $._config.name,
      image: $._config.image,
      imagePullPolicy: 'IfNotPresent',
      ports: [{
        containerPort: 3000,
        name: 'http',
      }],
      volumeMounts: [
        {
          mountPath: '/app/config',
          name: 'config',
        },{
          mountPath: '/app/config/logs',
          name: 'logs',
        }
      ],
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
            'checksum.config/md5': std.md5(std.toString($._config.configData)),
          },
          labels: $._config.commonLabels,
        },
        spec: {
          affinity: affinity($._config.name),
          containers: [c],
          restartPolicy: 'Always',
          serviceAccountName: $.serviceAccount.metadata.name,
          automountServiceAccountToken: true,
          enableServiceLinks: true,
          volumes: [
            {
              name: 'config',
              configMap: {
                name: $.configmap.metadata.name,
              },
            },{
              name: "logs",
              emptyDir: {},
            }
          ],
        },
      },
    },
  },


  [if std.objectHas(params, 'ingress') && std.objectHas(params.ingress, 'domain') && std.length(params.ingress.domain) > 0 then 'ingress']: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: $._metadata {
      annotations: $._config.ingress.annotations,
    },
    spec: {
      ingressClassName: $._config.ingress.className,
      tls: [{
        secretName: $._config.name + '-tls',
        hosts: [$._config.ingress.domain],
      }],
      rules: [{
        host: $._config.ingress.domain,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: $._config.name,
                port: {
                  name: $.service.spec.ports[0].name,
                },
              },
            },
          }],
        },
      }],
    },
  },
}
