#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep designate)
if [[ $service_test != '' ]]; then
  echo 'Existing designate service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ designate_service_password }} designate
openstack role add --project service --user designate admin
openstack service create --name designate --description "DNS" dns
openstack endpoint create --region RegionOne dns public {{ designate_public_endpoint }}
