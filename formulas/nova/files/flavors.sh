#!/bin/bash

# Loop through the flavors, if the flavor does not exist then add it
#
# openstack flavor create --ram  --disk  --ephemeral-disk  --vcpus  --public
# ex: openstack flavor create --ram 4096 --disk 16 --vcpus 8 --public cpu.large
# create-flavors.sls loops through the flavors, setting up the vars and executes openstack commands
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3


try=0
until [ $try -ge 5 ]
do
  openstack flavor create --ram {{ ram }} --disk {{ disk }} --vcpus {{ vcpus }} --public {{ flavor_name }} && break
  $try=[$try+1]
  sleep 5
done
if [[ $? = 0 ]]
then
  touch /etc/nova/flavors/{{ flavor_name }}
fi
