#!/bin/bash

# Script is used to update helm charts to latest versions using gitops.
# How it works:
# 1) Script looksup the HelmRelease object in `release.yaml` file to get the chart name and version.
# 2) It the reads HelmRepository object in `repository.yaml` file to get the repository URL.
# 3) It then uses helm to add a temporary repository and find latest varions of the chart.
# 4) It then updates the `release.yaml` file with the latest version.
# 5) It then removes temporary helm repository.

# Usage: ./helm-updater.sh <path-to-helm-charts>

# Get chart name from release.yaml file
CHART_NAME=$(yq .spec.chart.spec.chart < $1/release.yaml)

# Get chart version from release.yaml file
CHART_VERSION=$(yq .spec.chart.spec.version < $1/release.yaml)

# Get repository url from repository.yaml file
REPO_URL=$(yq .spec.url < $1/repository.yaml)

# Add temporary helm repository
TMP_REPO_NAME="tmp-$CHART_NAME"
helm repo add $TMP_REPO_NAME $REPO_URL

# Get latest chart version
export LATEST_CHART_VERSION=$(helm search repo $TMP_REPO_NAME/$CHART_NAME --versions | awk 'NR==2{print $2}')

# Update release.yaml file with latest chart version
yq -i '.spec.chart.spec.version=env(LATEST_CHART_VERSION)' $1/release.yaml

# Remove temporary helm repository
helm repo remove $TMP_REPO_NAME
