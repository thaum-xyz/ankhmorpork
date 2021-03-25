local defaults = {
  name: 'updater',
  namespace: error 'must provide namespace',
  schedule: '*/15 * * * *',
  domain: error 'must provide domain',
  image: error 'must provide curl image',
  // Secret needs to hold `username` and `password` keys.
  credentialsSecretName: error 'must provide secret name',
};

function(params) {
  local ext = self,
  config:: defaults + params,
  metadata:: {
    name: ext.config.name,
    namespace: ext.config.namespace,
  },

  cronjob: {
    apiVersion: 'batch/v1beta1',
    kind: 'CronJob',
    metadata: ext.metadata,
    spec: {
      successfulJobsHistoryLimit: 1,
      failedJobsHistoryLimit: 3,
      schedule: ext.config.schedule,
      jobTemplate: {
        spec: {
          template: {
            spec: {
              restartPolicy: 'OnFailure',
              containers: [{
                name: ext.config.name,
                image: ext.config.image,
                command: [
                  '/bin/sh',
                  '-c',
                  'curl --user $username:$password "https://www.ovh.com/nic/update?system=dyndns&hostname=%s&myip=$(curl https://ipecho.net/plain 2>/dev/null)" 2>/dev/null' % ext.config.domain,
                ],
                envFrom: [{
                  secretRef: { name: ext.config.credentialsSecretName },
                }],
              }],
            },
          },
        },
      },
    },
  },

}
