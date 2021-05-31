# Tips and tricks

## Run occ in container

`occ` needs to be run as `www-data` user, which is not able to use login shell. Using simple one-liner allows to run
`occ` in a specified container:

`kubectl exec -it nextcloud-0 -- su -s /bin/bash -c './occ db:add-missing-indices' www-data`
