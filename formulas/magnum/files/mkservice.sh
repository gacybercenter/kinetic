#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep magnum)
if [[ $service_test != '' ]]; then
  echo 'Existing magnum service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ magnum_service_password }} magnum
openstack role add --project service --user magnum admin
openstack service create --name magnum --description "OpenStack Container Infrastructure Management Service" container-infra
openstack endpoint create --region RegionOne container-infra public {{ magnum_public_endpoint }}
openstack endpoint create --region RegionOne container-infra internal {{ magnum_internal_endpoint }}
openstack endpoint create --region RegionOne container-infra admin {{ magnum_admin_endpoint }}


## magnum-specific changes
openstack domain create --description "Owns users and projects created by magnum" magnum
openstack user create --domain magnum --password {{ magnum_service_password }} magnum_domain_admin
openstack role add --domain magnum --user-domain magnum --user magnum_domain_admin admin
