#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep neutron)
if [[ $service_test != '' ]]; then
  echo 'Existing neutron service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ neutron_service_password }} neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public {{ neutron_public_endpoint }}
openstack endpoint create --region RegionOne network internal {{ neutron_internal_endpoint }}
openstack endpoint create --region RegionOne network admin {{ neutron_admin_endpoint }}
