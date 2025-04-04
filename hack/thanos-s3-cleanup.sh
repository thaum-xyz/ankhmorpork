#!/bin/bash

# Script used to clean up S3 bucket used by thanos. It iterates over folders in minio S3 bucket and checks if there
# is a file called `meta.json` or `deletion-mark.json`. Based on those files which it performs the following actions:
# - If it finds `deletion-mark.json` it deletes the folder and all folder versions from S3 bucket. This is because
#   thanos compactor already marked this folder as ready for deletion and compactor can leave the folder after is run.
# - If it doesn't find `meta.json` it also removes the folder and all folder versions from S3 bucket. This is because
#   without `meta.json` the folder is not used by thanos and it can be safely removed.

MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-""}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-""}"
MINIO_BUCKET="${MINIO_BUCKET:-"metrics/thanos"}"
MINIO_URL="${MINIO_URL:-"http://127.0.0.1:9000"}"
DRY_RUN="${DRY_RUN:-"true"}"

remove_folder() {
    if [ "$DRY_RUN" != "true" ]; then
        echo "Removing folder $1"
        mc rm --recursive --force --versions minio/$MINIO_BUCKET/$1
    else
        echo "Would remove folder $1"
    fi
}

# Log in to minio
mc alias set minio $MINIO_URL $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# Get the list of folders
folders=$(mc ls minio/$MINIO_BUCKET | awk '{print $5}')

all=0
deleted=0

# Loop through the folders
for folder in $folders; do
    # Check if there is a file called `deletion-mark.json` in the folder
    deletion_mark=$(mc ls minio/$MINIO_BUCKET/$folder | grep "deletion-mark.json")
    # Check if there is a file called `meta.json` in the folder
    meta=$(mc ls minio/$MINIO_BUCKET/$folder | grep "meta.json")

    echo -n "Checking $folder... " >&2
    all=$((all+1))

    # If there is a file called `deletion-mark.json` in the folder
    if [ -n "$deletion_mark" ]; then
        echo "Found deletion-mark.json" >&2
        remove_folder $folder
        deleted=$((deleted+1))
    # If there is no file called `meta.json` in the folder
    elif [ -z "$meta" ]; then
        echo "No meta.json found" >&2
        remove_folder $folder
        deleted=$((deleted+1))
    fi
    echo "" >&2
done

echo "All folders: $all, Deleted folders: $deleted" >&2
