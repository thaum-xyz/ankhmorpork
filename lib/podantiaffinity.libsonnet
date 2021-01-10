{
  podantiaffinity(value): {
    podAntiAffinity: {
      preferredDuringSchedulingIgnoredDuringExecution: [{
        weight: 100,
        podAffinityTerm: {
          labelSelector: {
            matchExpressions: [{
              key: 'app.kubernetes.io/name',
              operator: 'In',
              values: [value],
            }],
          },
          topologyKey: 'kubernetes.io/hostname',
        },
      }],
    },
  },
}
