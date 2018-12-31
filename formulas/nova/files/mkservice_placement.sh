#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep placement)
if [[ $service_test != '' ]]; then
  echo 'Existing placement service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ placement_service_password }} placement
openstack role add --project service --user placement admin
openstack service create --name nova --description "Placement API" placement
openstack endpoint create --region RegionOne placement public {{ placement_public_endpoint }}
openstack endpoint create --region RegionOne placement internal {{ placement_internal_endpoint }}
openstack endpoint create --region RegionOne placement admin {{ placement_admin_endpoint }}
