#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep manila)
if [[ $service_test != '' ]]; then
  echo 'Existing manila service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ manila_service_password }} manila
openstack role add --project service --user manila admin
openstack service create --name manila --description "OpenStack Shared File Systems" share
openstack service create --name manilav2 --description "OpenStack Shared File Systems v2" sharev2
openstack endpoint create --region RegionOne share public {{ manila_public_endpoint_v1 }}
openstack endpoint create --region RegionOne share internal {{ manila_internal_endpoint_v1 }}
openstack endpoint create --region RegionOne share admin {{ manila_admin_endpoint_v1 }}
openstack endpoint create --region RegionOne sharev2 public {{ manila_public_endpoint_v2 }}
openstack endpoint create --region RegionOne sharev2 internal {{ manila_internal_endpoint_v2 }}
openstack endpoint create --region RegionOne sharev2 admin {{ manila_admin_endpoint_v2 }}
