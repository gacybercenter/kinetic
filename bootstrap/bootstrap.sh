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
apt-get -y install curl

curl -sL https://bootstrap.saltstack.com | bash -s -- -M
