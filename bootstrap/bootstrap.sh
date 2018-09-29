#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run this script as the root user or with sudo"
  exit
fi

if [ $# -lt 6 ]; then
  echo 1>&2 "$0: not enough arguments"
  exit 2
fi

while getopts ":i:f:p:" opt; do
  case ${opt} in
    i )
      interface=$OPTARG
      ;;
    f )
      fileroot=$OPTARG
      ;;
    p )
      pillar=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG." 1>&2
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
apt-get -y install qemu-kvm qemu-utils genisoimage curl libvirt-clients libvirt-daemon-system

## Directories

mkdir -p /kvm/images
mkdir -p /kvm/vms/salt/data
mkdir -p /kvm/vms/pxe/data

## Images

if [ ! -f /kvm/images/debian9.raw ]
then
  local_image_hash=bad
else
  local_image_hash=$(sha512sum /kvm/images/debian9.raw | awk '{ print $1 }')
fi

remote_image_hash=$(curl https://cdimage.debian.org/cdimage/openstack/current-9/SHA512SUMS | grep $local_image_hash | awk '{ print $1 }')

if [ "$local_image_hash" == "$remote_image_hash" ]
then
  echo No new image needed.  Skipping download.
else
  echo Image hash mismatch.  Re-downloading.
  wget https://cdimage.debian.org/cdimage/openstack/current-9/debian-9-openstack-amd64.raw -O /kvm/images/debian9.raw
fi


## salt
if [ ! -f /kvm/vms/salt/disk0.raw ]
then
  cp /kvm/images/debian9.raw /kvm/vms/salt/disk0.raw
fi
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed "s/{{ name }}/salt/g; s/{{ interface }}/$interface/g" > /kvm/vms/salt/config.xml
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.metadata | sed "s/{{ name }}/salt/g" > /kvm/vms/salt/data/meta-data
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.userdata | sed "s/{{ opts }}/-M -X -i salt -J '{ \"default_top\": \"base\", \"fileserver_backend\": [ \"git\" ], \"ext_pillar\": [ { \"git\": [ { \"master $pillar\": [ { \"env\": \"base\" } ] } ] } ], \"ext_pillar_first\": true, \"gitfs_remotes\": [ { \"$fileroot\": [ { \"saltenv\": [ { \"base\": [ { \"ref\": \"master\" } ] } ] } ] } ], \"gitfs_saltenv_whitelist\": [ \"base\" ] }'/g" > /kvm/vms/salt/data/user-data
genisoimage -o /kvm/vms/salt/config.iso -V cidata -r -J /kvm/vms/salt/data/meta-data /kvm/vms/salt/data/user-data
virsh create /kvm/vms/salt/config.xml

##pxe
if [ ! -f /kvm/vms/pxe/disk0.raw ]
then
  cp /kvm/images/debian9.raw /kvm/vms/pxe/disk0.raw
fi
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed "s/{{ name }}/pxe/g; s/{{ interface }}/$interface/g" > /kvm/vms/pxe/config.xml
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.metadata | sed "s/{{ name }}/pxe/g" > /kvm/vms/pxe/data/meta-data
curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.userdata | sed "s/{{ opts }}/-X -i pxe/g" > /kvm/vms/pxe/data/user-data
genisoimage -o /kvm/vms/pxe/config.iso -V cidata -r -J /kvm/vms/pxe/data/meta-data /kvm/vms/pxe/data/user-data
virsh create /kvm/vms/pxe/config.xml
