# Tips and tricks

## Run occ in container

`occ` needs to be run as `www-data` user, which is not able to use login shell. Using simple one-liner allows to run
`occ` in a specified container:

`kubectl exec -it nextcloud-0 -- su -s /bin/bash -c './occ db:add-missing-indices' www-data`

## Maintenance mode

ON:  `kubectl exec -it nextcloud-0 -- su -s /bin/bash -c './occ maintenance:mode --on' www-data`
OFF: `kubectl exec -it nextcloud-0 -- su -s /bin/bash -c './occ maintenance:mode --off' www-data`

## Database recovery

0. Set `RESTIC_PASSWORD`, `RESTIC_REPOSITORY`, `B2_ACCOUNT_ID`, `B2_ACCOUNT_KEY`
1. `restic restore latest --target .`
2. Get mysql root password - `export MYSQL_ROOT_PASSWORD=$(kubectl get secret mysql-creds --template={{.data.root_pass}} | base64 --decode)`
3. Get mysql pod - `export POD=$(kubectl get pod -l app.kubernetes.io/name=mysql -o jsonpath="{.items[0].metadata.name}")`
3. `kubectl exec -i ${POD} -- mysql -uroot -p${MYSQL_ROOT_PASSWORD} cloud < cloud_dump.sql`
