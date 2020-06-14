#!/bin/bash

REPO_DIR=$(pwd)

metrics() {
	if [ "$UPDATE_STATE" -eq "0" ]; then
		error=0
		success=1
	else
		success=0
		error=1
	fi
	end="$(date +%s)"
        if [ -z "$PUSHGATEWAY_URL" ]; then
                echo "INFO: PUSHGATEWAY_URL not defined, metrics won't be sent"
        else
                cat <<EOF | curl --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/deploy/instance/$(hostname)"
# HELP deployment_duration_seconds Time spent on deploying stack
# TYPE deployment_duration_seconds gauge
deployment_duration_seconds $((end - START))
# HELP deployment_status_success Return 1 if deployment was successful
# TYPE deployment_status_success gauge
deployment_status_success $success
# HELP deployment_status_failure Return 1 if deployment failed
# TYPE deployment_status_failure gauge
deployment_status_failure $success
EOF
                echo "$(date +"%F %T") INFO: Statistics exported. All done."
        fi
}

update_repo() {
	echo "INFO: Updating code repository"
	# Clean repository and revert all local changes as well as 10 prev commits
	git clean -xfd
	git reset --hard HEAD

	## Synchronize repository
	prev=$(git rev-parse HEAD)
	git reset --hard HEAD~10
	git pull

	if git diff --name-only --diff-filter=AMDR --cached "${prev}" | grep -q "ansible"; then
		return 1
	fi
	return 0
}

update_hosts() {
	if curl -fsSL "${ARA_SERVER}/api/" >/dev/null && python3 -c "import ara.setup.callback_plugins"; then
		export ARA_API_CLIENT="http"
		export ARA_API_SERVER="${ARA_SERVER}"
		export ANSIBLE_CALLBACK_PLUGINS="$(python3 -m ara.setup.callback_plugins)"
	else
		>&2 echo "WARN: Couldn't contact ARA server. Ansible run won't be recorded."
	fi
	echo "INFO: Updating services"
	# Force roles download once a day, around midnight (THIS IS TIED TO CRONTAB JOB)
	local params=""
	if [ "$(date +%H)" -eq 0 ] && [ "$(date +%M)" -lt 5 ]; then
		params="--force"
	fi

	cd "${REPO_DIR}/ansible"
	ansible-galaxy install $params -r roles/requirements.yml
	ansible-playbook 00_site.yml 3>&1 || exit 1
}

START="$(date +%s)"
echo "Start update at $(date)"
UPDATE_STATE=1 # 0 - update done, 1 - update failed
ARA_SERVER="$1"
PUSHGATEWAY_URL="$2"

trap metrics EXIT
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_DIR="$(pwd)"

if update_repo; then
	UPDATE_STATE=0
	exit 0
fi

update_hosts

UPDATE_STATE=0
