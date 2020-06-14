#!/bin/bash

METRICS_FILE="/var/lib/node_exporter/deployment.prom"
REPO_DIR=$(pwd)
RUN_AS="root"

metrics() {
    echo "INFO: Updating metrics"
    local end success error
    if [ ! -f "$METRICS_FILE" ]; then
        success=0
        error=0
    else
        error=$(grep "error" "${METRICS_FILE}" | cut -d' ' -f2)
        success=$(grep "success" "${METRICS_FILE}" | cut -d' ' -f2)
    fi
    if [ "$UPDATE_STATE" -eq "0" ]; then
        error=0
        success=$(( success + 1))
    else
        success=0
        error=$(( error + 1))
    fi
    end="$(date +%s)"
    METRICS=$(mktemp)
    cat <<EOF > "$METRICS"
# HELP deployment_duration_seconds Time spent on deploying stack
# TYPE deployment_duration_seconds gauge
deployment_duration_seconds $((end - START))
# HELP deployment_total Total number of deployments
# TYPE deployment_total counter
deployment_total{status="error"} $error
deployment_total{status="success"} $success
EOF
    chmod a+r "$METRICS"
    mv "$METRICS" "$METRICS_FILE"
}

update_repo() {
	echo "INFO: Updating code repository"
	# Clean repository and revert all local changes as well as 10 prev commits
	su "$RUN_AS" -c "git clean -xfd"
	su "$RUN_AS" -c "git reset --hard HEAD"

	## Synchronize repository
	prev=$(git rev-parse HEAD)
	su "$RUN_AS" -c "git reset --hard HEAD~10"
	su "$RUN_AS" -c "git pull"

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
	su "$RUN_AS" ansible-galaxy install $params -r roles/requirements.yml
	su "$RUN_AS" ansible-playbook 00_site.yml 3>&1 || exit 1
}

START="$(date +%s)"
echo "Start update at $(date)"
UPDATE_STATE=1 # 0 - update done, 1 - update failed
ARA_SERVER="$1"

trap metrics EXIT
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
	echo "ERR: Please run as root"
	exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_DIR="$(pwd)"
RUN_AS="$(stat --format '%U' .git)"

if update_repo; then
	UPDATE_STATE=0
	exit 0
fi

update_hosts

UPDATE_STATE=0
