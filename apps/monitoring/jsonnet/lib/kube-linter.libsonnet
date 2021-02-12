local ignoreCheck(name, comment) = {
  metadata+: {
    annotations+: {
      ['ignore-check.kube-linter.io/' + name]: comment,
    },
  },
};

{
  alertmanager+: {
    service+: ignoreCheck('dangling-service', 'Check is incompatible with prometheus-operator CRDs'),
  },
  prometheus+: {
    service+: ignoreCheck('dangling-service', 'Check is incompatible with prometheus-operator CRDs'),
  },
}
