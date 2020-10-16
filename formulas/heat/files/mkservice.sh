#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep heat)
if [[ $service_test != '' ]]; then
  echo 'Existing heat service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ heat_service_password }} heat
openstack role add --project service --user heat admin
openstack service create --name heat --description "Orchestration" orchestration
openstack service create --name heat-cfn --description "Orchestration" cloudformation
openstack endpoint create --region RegionOne orchestration public {{ heat_public_endpoint }}
openstack endpoint create --region RegionOne orchestration internal {{ heat_internal_endpoint }}
openstack endpoint create --region RegionOne orchestration admin {{ heat_admin_endpoint }}
openstack endpoint create --region RegionOne cloudformation public {{ heat_public_endpoint_cfn }}
openstack endpoint create --region RegionOne cloudformation internal {{ heat_internal_endpoint_cfn }}
openstack endpoint create --region RegionOne cloudformation admin {{ heat_admin_endpoint_cfn }}


## heat-specific changes
openstack domain create --description "Stack projects and users" heat
openstack user create --domain heat --password {{ heat_service_password }} heat_domain_admin
openstack role add --domain heat --user-domain heat --user heat_domain_admin admin
openstack role create heat_stack_owner
openstack role create heat_stack_user
