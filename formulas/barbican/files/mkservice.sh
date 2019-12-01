#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep barbican)
if [[ $service_test != '' ]]; then
  echo 'Existing barbican service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ barbican_service_password }} barbican
openstack role add --project service --user barbican admin
openstack service create --name barbican --description "Key Manager" key-manager
openstack endpoint create --region RegionOne key-manager public {{ barbican_public_endpoint }}
openstack endpoint create --region RegionOne key-manager internal {{ barbican_internal_endpoint }}
openstack endpoint create --region RegionOne key-manager admin {{ barbican_admin_endpoint }}
