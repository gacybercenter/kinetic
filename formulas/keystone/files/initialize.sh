#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3


/bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap --bootstrap-password {{ admin_password }} \
  --bootstrap-admin-url {{ admin_endpoint }} \
  --bootstrap-internal-url {{ internal_endpoint }} \
  --bootstrap-public-url {{ public_endpoint }} \
  --bootstrap-region-id RegionOne

project_test=$(openstack project list | grep service)

if [[ $project_test != '' ]]; then
  echo 'Existing service project detected...skipping creation...'
  echo $project_test
else
  openstack project create --domain default --description "Service Project" service
fi

user_role_test=$(openstack role list | grep user)

if [[ $user_role_test != '' ]]; then
  echo 'Existing user role detected...skipping creation...'
  echo $user_role_test
else
  openstack role create user
fi

service_user_test=$(openstack user list | grep keystone)

if [[ $service_user_test != '' ]]; then
  echo 'Existing keystone service user detected...skipping creation...'
  echo $service_user_test
else
openstack user create --domain default --password {{ keystone_service_password }} keystone
openstack role add --project service --user keystone admin 
fi

ldap_domain_test=$(openstack domain list | grep "LDAP Domain")

if [[ $ldap_domain_test != '' ]]; then
  echo 'Existing ldap domain detected...skipping creation...'
  echo $ldap_domain_test
else
  openstack domain create --description "LDAP Domain" ldap
fi
