#!/bin/bash

# Trim LVM thin volumes using fstrim command.

# Find all thin volumes
volumes=$(lvs --noheadings -o lv_attr,vg_name,lv_name | grep "^  V" | awk '{print $2" "$3}' | sed 's/-/--/g' | sed 's/ /-/g')

# Trim all mounted volumes
for volume in $volumes; do
  mountpoint=$(grep "$volume" /proc/mounts | head -n1 | awk '{print $2}')
  if [ -n "$mountpoint" ]; then
    echo "Trimming $volume ($mountpoint)"
    fstrim -v $mountpoint
  fi
done
