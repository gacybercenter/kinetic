#!/bin/bash

iso_directory="/srv/tftp/jammy"
target_directory="/srv/tftp/jammy"

mkdir -p "$target_directory/amd64"
mkdir -p "$target_directory/arm64"

extract_iso_contents() {
    iso_file="$1"
    architecture="$2"

    mount_point="/mnt/iso_mount"
    mkdir -p "$mount_point"

    mount "$iso_file" "$mount_point"

    cp -af "$mount_point/casper/vmlinuz" "$target_directory/$architecture/vmlinuz"
    cp -af "$mount_point/casper/initrd" "$target_directory/$architecture/initrd"

    umount "$mount_point"

    rmdir "$mount_point"
}

find "$iso_directory" -type f -name "*.iso" | while IFS= read -r iso_file; do
    if [[ $iso_file == *"amd64"* ]]; then
        architecture="amd64"
    elif [[ $iso_file == *"arm64"* ]]; then
        architecture="arm64"
    else
        echo "Unknown architecture for $iso_file. Skipping."
        continue
    fi

    echo "Processing $iso_file for $architecture"

    extract_iso_contents "$iso_file" "$architecture"
done