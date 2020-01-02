#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep zun)

if [[ $service_test != '' ]]; then
  echo 'Existing zun service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ zun_service_password }} zun
openstack role add --project service --user zun admin
openstack service create --name zun --description "Container Service" container
openstack endpoint create --region RegionOne container public {{ zun_public_endpoint }}
openstack endpoint create --region RegionOne container internal {{ zun_internal_endpoint }}
openstack endpoint create --region RegionOne container admin {{ zun_admin_endpoint }}
