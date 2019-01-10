#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep kuryr)

if [[ $service_test != '' ]]; then
  echo 'Existing kuryr service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ kuryr_service_password }} kuryr
openstack role add --project service --user kuryr admin
