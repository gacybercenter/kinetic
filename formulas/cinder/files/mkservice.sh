#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep cinder)
if [[ $service_test != '' ]]; then
  echo 'Existing cinder service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ cinder_service_password }} cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne volumev2 public {{ cinder_public_endpoint_v2 }}
openstack endpoint create --region RegionOne volumev2 internal {{ cinder_internal_endpoint_v2 }}
openstack endpoint create --region RegionOne volumev2 admin {{ cinder_admin_endpoint_v2 }}
openstack endpoint create --region RegionOne volumev3 public {{ cinder_public_endpoint_v3 }}
openstack endpoint create --region RegionOne volumev3 internal {{ cinder_internal_endpoint_v3 }}
openstack endpoint create --region RegionOne volumev3 admin {{ cinder_admin_endpoint_v3 }}
