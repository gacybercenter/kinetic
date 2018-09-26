#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run this script as the root user or with sudo"
  exit
fi

if [ $# -lt 1 ]; then
  echo 1>&2 "$0: not enough arguments"
  exit 2
fi

while getopts ":i:" opt; do
  case ${opt} in
    i )
      interface=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG.  The only valid option is -i, which specifies the bridged management interface on this device" 1>&2
      exit
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      exit
      ;;
  esac
done

DEBIAN_FRONTEND=noninteractive

## Packages
apt-get update
apt-get -y dist-upgrade
apt-get -y install qemu-kvm qemu-utils genisoimage curl

## Directories

mkdir -p /kvm/images
mkdir -p /kvm/vms/salt
mkdir /kvm/vms/pxe

## Images

local_image_hash=$(sha512sum /kvm/images/debian9.raw | awk '{ print $1 }')
remote_image_hash=$(curl https://cdimage.debian.org/cdimage/openstack/current-9/SHA512SUMS | grep $local_image_hash | awk '{ print $1 }')

if [ "$local_image_hash" == "$remote_image_hash" ]
then
  echo No new image needed.  Skipping download.
else
  echo Image hash mismatch.  Re-downloading.
  wget https://cdimage.debian.org/cdimage/openstack/current-9/debian-9-openstack-amd64.raw -O /kvm/images/debian9.raw
fi

## Configuration

curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed "s/{{ name }}/salt/g; s/{{ interface }}/$interface/g" > /kvm/vms/salt/config.xml
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed "s/{{ name }}/pxe/g; s/{{ interface }}/$interface/g" > /kvm/vms/pxe/config.xml

curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.metadata | sed "s/{{ name }}/salt/g" > /kvm/vms/salt/data/meta-data
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.metadata | sed "s/{{ name }}/pxe/g" > /kvm/vms/pxe/meta-data

curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.userdata | sed "s/{{ opts }}/-M -X -i salt/g" > /kvm/vms/salt/data/user-data
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.userdata | sed "s/{{ opts }}/-X -i pxe/g" > /kvm/vms/pxe/data/user-data

genisoimage -o /kvm/vms/salt/config.iso -V cidata -r -J /kvm/vms/salt/data/meta-data /kvm/vms/salt/data/user-data
genisoimage -o /kvm/vms/pxe/config.iso -V cidata -r -J /kvm/vms/salt/pxe/meta-data /kvm/vms/salt/pxe/user-data

virsh create /kvm/vms/salt/config.xml
virsh create /kvm/vms/pxe/config.xml
