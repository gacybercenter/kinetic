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


echo "Check flavor existence"
flavorexistcheck=$(openstack flavor show {{ flavor_name }} )
if [[ $? != 0 ]]; then
    # flavor does not exist.  if the openstack command fails for a general failure it will fall here as well
    openstack flavor create --ram {{ ram }} --disk {{ disk }} --vcpus {{ vcpus }} --public {{ flavor_name }}
else
    echo "flavor - {{ flavor_name }} - exists already.  Exiting..."
fi
