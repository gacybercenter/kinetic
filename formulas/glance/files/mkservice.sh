#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep glance)
if [[ $service_test != '' ]]; then
  echo 'Existing glance service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ glance_service_password }} glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public {{ glance_public_endpoint }}
openstack endpoint create --region RegionOne image internal {{ glance_internal_endpoint }}
openstack endpoint create --region RegionOne image admin {{ glance_admin_endpoint }}
