#!/bin/bash

REPO_DIR=$(pwd)

metrics() {
	code="$?"
	end="$(date +%s)"
	if [ -z "$PUSHGATEWAY_URL" ]; then
		echo "INFO: PUSHGATEWAY_URL not defined, metrics won't be sent"
		exit $code
	fi
	cat <<EOF | curl --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/deploy/instance/$(hostname)"
# HELP deployment_start_last_timestamp_seconds Time whan deployment started
# TYPE deployment_start_last_timestamp_seconds counter
deployment_start_last_timestamp_seconds ${START}
# HELP deployment_end_last_timestamp_seconds Time when deployment ended
# TYPE deployment_end_last_timestamp_seconds counter
deployment_end_last_timestamp_seconds ${end}
# HELP deployment_exit_code Exit code returned by deployment script
# TYPE deployment_exit_code
deployment_exit_code $code
EOF
	echo "INFO: Statistics exported. All done."
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
echo "INFO: Start update at $(date)"
ARA_SERVER="$1"
PUSHGATEWAY_URL="$2"

trap metrics EXIT
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_DIR="$(pwd)"

if update_repo; then
	exit 0
fi

update_hosts
