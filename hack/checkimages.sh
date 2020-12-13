#!/bin/bash

set -euo pipefail

CPU_ARCHS="amd64 arm64 arm"
MULTI_ARCH_EXCLUDED=$(
	cat <<EOM
quay.io/external_storage/nfs-client-provisioner-arm
quay.io/external_storage/nfs-client-provisioner
quay.io/paulfantom/nfs-client-provisioner
eu.gcr.io/k8s-artifacts-prod/descheduler/descheduler
homeassistant/aarch64-homeassistant
plexinc/pms-docker
quay.io/paulfantom/plex_exporter
metalmatze/transmission-exporter
haugene/transmission-openvpn
mariadb
oliver006/redis_exporter
hipages/php-fpm_exporter
xperimental/nextcloud-exporter
nginx/nginx-prometheus-exporter
allangood/holiday_exporter
quay.io/superq/smokeping-prober-linux-arm64
quay.io/prometheus/mysqld-exporter
intel/intel-gpu-plugin
rancher/k3s-upgrade
EOM
)

FAIL="[ \e[1m\e[31mFAIL\e[0m ]"
SKIP="[ \e[1m\e[33mSKIP\e[0m ]"
OK="[  \e[1m\e[32mOK\e[0m  ]"

check_cross_compatibility() {
	local image="${1}"
	local manifest="${2}"
	local err=0
	local arch_list

	for exclude in ${MULTI_ARCH_EXCLUDED}; do
		if [[ "${image}" =~ ${exclude} ]]; then
			echo -e "$SKIP Validating cross-arch compatibility for \e[1m${image}\e[0m"
			return
		fi
	done

	arch_list="$(echo "${manifest}" | jq -cr '..| .architecture?, .Architecture? | select(type != "null") | select(. != "" )' | sort | uniq)"
	for arch in ${CPU_ARCHS}; do
		if ! grep -q "${arch}$" <<<"$arch_list"; then
			echo -e "$FAIL Image \e[1m${image}\e[0m does not support ${arch} !"
			err=1
		fi
	done
	if [ "$err" -ne 0 ]; then
		exit 129
	fi
}

# Go to top-level
cd "$(git rev-parse --show-toplevel)"

IMAGES=""

for file in $(find apps/ base/ -name *.yaml -exec grep "image" -l {} \;); do
	new=$(gojsontoyaml -yamltojson <"$file" | jq -cr '..| .image? | select(type == "string")')
	IMAGES="${new} ${IMAGES}"
done

pids=()
for image in $(echo -e "${IMAGES}" | tr ' ' '\n' | sort -f | uniq); do
	(
		info=$(manifest-tool inspect --raw "${image}" 2>&1)
		# Handles 429 Too Many Requests response
		if [[ "$info" =~ "429 Too Many Requests" ]]; then
			echo -e "$SKIP Too many retries when trying to validate cross-arch compatibility for \e[1m${image}\e[0m - $info"
			exit 0
		fi

		count=0
		until check_cross_compatibility "${image}" "${info}"; do
			sleep 15
			count=$((count++))
			if [ $count -gt 10 ]; then
				break
			fi
		done
		if [ $count -gt 10 ]; then
			echo -e "$FAIL Image \e[1m${image}\e[0m is not compatible with system architecture"
		else
			echo -e "$OK Image \e[1m${image}\e[0m is compatible"
		fi
	) &
	pids+=("$!")
	sleep "$((RANDOM % 10))" # Add some delay to prevent DDoSing registry
done

EXIT_CODE=0
for job in "${pids[@]}"; do
	CODE=0
	wait ${job} || CODE=$?
	if [[ "${CODE}" != "0" ]]; then
		echo "At least one image is not compatible with specified CPU architectures"
		EXIT_CODE=$CODE
	fi
done

exit $EXIT_CODE
