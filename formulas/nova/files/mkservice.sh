#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep nova)
if [[ $service_test != '' ]]; then
  echo 'Existing nova service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ nova_service_password }} nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public {{ nova_public_endpoint }}
openstack endpoint create --region RegionOne compute internal {{ nova_internal_endpoint }}
openstack endpoint create --region RegionOne compute admin {{ nova_admin_endpoint }}
