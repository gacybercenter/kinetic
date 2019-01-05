#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep swift)
if [[ $service_test != '' ]]; then
  echo 'Existing swift service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ swift_service_password }} swift \
openstack role add --project service --user swift admin \
openstack service create --name swift --description "OpenStack Object Storage" object-store \
openstack endpoint create --region RegionOne object-store public {{ swift_public_endpoint }}   \
openstack endpoint create --region RegionOne object-store internal {{ swift_internal_endpoint }}   \
openstack endpoint create --region RegionOne object-store admin {{ swift_admin_endpoint }}   \
