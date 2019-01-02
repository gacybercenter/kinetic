#!/bin/bash

export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

if [ `openstack project list | grep {{ project }} -c` -eq 0 ]; then
  echo "INFO: CREATED {{ project }} and set quotas"
  openstack project create {{ project }} --or-show
  openstack quota set --ram {{ maxram }} --instances {{ maxinstances }} --cores {{ maxvcpus }} --gigabytes {{ gigabytes }} {{ project }}
fi
