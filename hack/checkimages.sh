#!/bin/bash

set -euo pipefail

CPU_ARCHS="amd64 arm64 arm"
MULTI_ARCH_EXCLUDED=$( cat <<EOM
quay.io/external_storage/nfs-client-provisioner-arm
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
EOM
)

check_cross_compatibility() {
        local image="${1}"
        local manifest="${2}"
        local err=0
        local arch_list

        for exclude in ${MULTI_ARCH_EXCLUDED}; do
                if [[ "${image}" =~ ${exclude} ]]; then
                        echo "WARN: Skipping validating cross-arch compatibility for ${image}"
                        return
                fi
        done

        arch_list="$(echo "${manifest}" | jq -cr '..| .architecture?, .Architecture? | select(type != "null") | select(. != "" )'  | sort | uniq)"
        for arch in ${CPU_ARCHS}; do
                if ! grep -q "${arch}$" <<< "$arch_list"; then
                        echo "ERR : Image ${image} does not support ${arch} !"
                        err=1
                fi
        done
        if [ "$err" -ne 0 ]; then
                exit 129
        else
                echo "INFO: Image ${image} is compatible with specified CPU architectures"
        fi
}



# Go to top-level
cd "$(git rev-parse --show-toplevel)"

IMAGES=""

for file in $(find apps/ base/ -name *.yaml -exec grep "image" -l {} \;); do
        new=$(gojsontoyaml -yamltojson < "$file" | jq -cr '..| .image? | select(type != "null")')
        IMAGES="${new} ${IMAGES}"
done

pids=()
for image in $(echo -e "${IMAGES}" | tr ' ' '\n' | sort -f | uniq); do
        (
                echo "INFO: Inspecting ${image} ..."
                info=$(manifest-tool inspect --raw "${image}")
                check_cross_compatibility "${image}" "${info}"
        ) &
        pids+=("$!")
done

EXIT_CODE=0
for job in "${pids[@]}"; do
        CODE=0;
        wait ${job} || CODE=$?
        if [[ "${CODE}" != "0" ]]; then
                echo "At least one image is not compatible with specified CPU architectures" ;
                EXIT_CODE=$CODE;
        fi
done

exit $EXIT_CODE
