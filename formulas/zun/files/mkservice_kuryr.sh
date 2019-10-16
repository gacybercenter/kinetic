#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

user_test=$(openstack user list | grep kuryr)

if [[ $user_test != '' ]]; then
  echo 'Existing kuryr user detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ kuryr_service_password }} kuryr
openstack role add --project service --user kuryr admin
