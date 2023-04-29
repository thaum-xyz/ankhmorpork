local defaults = {
  local defaults = self,
  name: 'tandoor',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {
    requests: { cpu: '120m', memory: '200Mi' },
    //limits: { cpu: '400m', memory: '600Mi' },
  },
  commonLabels:: {
    'app.kubernetes.io/name': 'tandoor',
    'app.kubernetes.io/version': defaults.version,
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  ingress: {
    domain: '',
    className: 'nginx',
    metadata: {},
  },
};

function(params) {
  _config:: defaults + params,
  _metadata:: {
    name: $._config.name,
    namespace: $._config.namespace,
    labels: $._config.commonLabels,
  },

  common: {
    pvcMedia:: {},
    pvcStatic:: {},
    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: $._metadata + $._config.ingress.metadata,
      spec: {
        ingressClassName: $._config.ingress.className,
        rules: [{
          host: $._config.ingress.domain,
          http: {
            paths: [
              {
                backend: {
                  service: {
                    name: $.app.service.metadata.name,
                    port: {
                      name: $.app.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/',
                pathType: 'Prefix',
              },
              {
                backend: {
                  service: {
                    name: $.static.service.metadata.name,
                    port: {
                      name: $.static.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/media',
                pathType: 'Prefix',
              },
              {
                backend: {
                  service: {
                    name: $.static.service.metadata.name,
                    port: {
                      name: $.static.service.spec.ports[0].name,
                    },
                  },
                },
                path: '/static',
                pathType: 'Prefix',
              },
            ],
          },
        }],
        tls: [{
          hosts: [$._config.ingress.domain],
          secretName: $._config.name + '-tls',
        }],
      },
    },
  },

  app: {
    serviceAccount:: {},
    config:: {},
    secretKey:: {},
    service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: $._metadata,
      spec: {
        ports: [{
          name: 'gunicorn',
          port: 8080,
          protocol: 'TCP',
          targetPort: 'gunicorn',
        }],
        //selector: $._config.selectorLabels.
        selector: {  // TODO: remove
          app: 'recipes',
        },
      },
    },
    statefulSet:: {},
  },

  static: {
    serviceAccount:: {},
    config:: {},
    service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: $._metadata { name+: '-static' },
      spec: {
        ports: [{
          name: 'http',
          port: 80,
          protocol: 'TCP',
          targetPort: 'http',
        }],
        selector: {  // TODO: fix this
          app: 'static',
        },
      },
    },
    deployment:: {},
  },
}
