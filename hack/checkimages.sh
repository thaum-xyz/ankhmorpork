#!/bin/bash

set -euo pipefail

CPU_ARCHS="amd64 arm64"
MULTI_ARCH_EXCLUDED=$(
	cat <<EOM
quay.io/external_storage/nfs-client-provisioner
eu.gcr.io/k8s-artifacts-prod/descheduler/descheduler
homeassistant/aarch64-homeassistant
plexinc/pms-docker
quay.io/paulfantom/plex_exporter
metalmatze/transmission-exporter
mariadb
oliver006/redis_exporter
hipages/php-fpm_exporter
xperimental/nextcloud-exporter
allangood/holiday_exporter
quay.io/superq/smokeping-prober-linux-arm64
quay.io/prometheus/mysqld-exporter
intel/intel-gpu-plugin
nvidia/k8s-device-plugin
EOM
)

FAIL="[ \e[1m\e[31mFAIL\e[0m ]"
SKIP="[ \e[1m\e[33mSKIP\e[0m ]"
OK="[  \e[1m\e[32mOK\e[0m  ]"
INFO="[ \e[1m\e[34mSKIP\e[0m ]"

check_cross_compatibility() {
	local image="${1}"
	local manifest="${2}"
	local arch_list
	local arch_fail=""

	arch_list="$(echo "${manifest}" | jq -cr '..| .architecture?, .Architecture? | select(type != "null") | select(. != "" )' | sort | uniq)"
	for arch in ${CPU_ARCHS}; do
		if ! grep -q "${arch}$" <<<"$arch_list"; then
			arch_fail="${arch_fail} ${arch}"
		fi
	done
	if [ "$arch_fail" != "" ]; then
		echo -e "$FAIL Image \e[1m${image}\e[0m does not support following architectures: ${arch_fail}!"
		exit 129
	fi
}

# Go to top-level
cd "$(git rev-parse --show-toplevel)"

# Find all images used in environment
DETECTED_IMAGES=""
for file in $(find apps/ base/ -name *.yaml -exec grep "image" -l {} \;); do
	new=$(gojsontoyaml -yamltojson <"$file" | jq -cr '..| .image? | select(type == "string")')
	DETECTED_IMAGES="${new} ${DETECTED_IMAGES}"
done

# Check if exclusion list is up to date
for image in ${MULTI_ARCH_EXCLUDED}; do
	grep "${image}" -q -R apps/ base/ || echo -e "$INFO Excluded image \e[1m${image}\e[0m no longer used"
done

# Remove duplicates, sanitize, and check if image shoud be skipped
IMAGES=""
for image in $(echo -e "${DETECTED_IMAGES}" | tr ' ' '\n' | sort -f | uniq | grep -v '^$'); do
	# remove version
	prefix=$(echo "$image" | tr ':' '\n' | head -n1)
	if [[ ${MULTI_ARCH_EXCLUDED} =~ "${prefix}" ]]; then
		echo -e "$SKIP Validating cross-arch compatibility for \e[1m${image}\e[0m"
	else
		IMAGES="${IMAGES} ${image}"
	fi
done

# In parallel check image manifests
pids=()
for image in ${IMAGES}; do
	(
		sleep "$((RANDOM % 10))" # Add some delay to prevent DDoSing registry
		info=$(manifest-tool inspect --raw "${image}" 2>&1 || :)
		# Handles 429 Too Many Requests response
		if [[ "$info" =~ "You have reached your pull rate limit" ]] || [[ "$info" =~ "429 Too Many Requests" ]]; then
			echo -e "$SKIP Too many retries when trying to validate cross-arch compatibility for \e[1m${image}\e[0m"
			exit 0
		fi
		if echo "${info}" | grep -q 'level=fatal'; then
			echo -e "$FAIL Encountered fatal problems with \e[1m${image}\e[0m: ${info/*msg=/}"
			exit 1
		fi

		check_cross_compatibility "${image}" "${info}" || exit 1
		echo -e "$OK Image \e[1m${image}\e[0m is compatible"
	) &
	pids+=("$!")
done

EXIT_CODE=0
for job in "${pids[@]}"; do
	CODE=0
	wait ${job} || CODE=$?
	if [[ "${CODE}" != "0" ]]; then
		echo -e "$FAIL Detected problems with at least one image"
		EXIT_CODE=$CODE
	fi
done

exit $EXIT_CODE
