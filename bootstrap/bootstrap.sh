#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run this script as the root user or with sudo"
  exit
fi

while getopts ":i:" opt; do
  case ${opt} in
    i )
      interface=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG.  The only valid option is -i, which specifies the bridged management interface on this device" 1>&2
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      ;;
  esac
done

DEBIAN_FRONTEND=noninteractive

## Packages
apt-get update
apt-get -y dist-upgrade
apt-get -y install qemu-kvm qemu-utils genisoimage bridge-utils

## Networking

address=$(hostname -I)

mkdir -p /kvm/images
mkdir -p /kvm/vms/salt
mkdir /kvm/vms/dnsmasq

wget https://cdimage.debian.org/cdimage/openstack/current-9/debian-9-openstack-amd64.raw -O /kvm/images/debian9.raw
curl https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed 's/{{ name }}/salt/g' > /kvm/vms/salt/config.xml
curl https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/common.xml | sed 's/{{ name }}/dnsmasq/g' > /kvm/vms/dnsmasq/config.xml
