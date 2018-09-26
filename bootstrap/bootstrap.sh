#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run this script as the root user or with sudo"
  exit
fi

DEBIAN_FRONTEND=noninteractive

## Packages
apt-get update
apt-get -y dist-upgrade
apt-get -y install curl

curl -sL https://bootstrap.saltstack.com | bash -s -- -M
