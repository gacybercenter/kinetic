#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep sahara)
if [[ $service_test != '' ]]; then
  echo 'Existing sahara service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ sahara_service_password }} sahara
openstack role add --project service --user sahara admin
openstack service create --name sahara --description "Sahara Data Processing" data-processing
openstack endpoint create --region RegionOne data-processing public {{ sahara_public_endpoint }}
openstack endpoint create --region RegionOne data-processing internal {{ sahara_internal_endpoint }}
openstack endpoint create --region RegionOne data-processing admin {{ sahara_admin_endpoint }}
