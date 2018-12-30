#!/bin/bash

/bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap --bootstrap-password {{ admin_password }} \
  --bootstrap-admin-url {{ admin_endpoint }} \
  --bootstrap-internal-url {{ internal_endpoint }} \
  --bootstrap-public-url {{ public_endpoint }} \
  --bootstrap-region-id RegionOne

project_test=$(openstack project list \
--os-username admin \
--os-password {{ admin_password }} \
--os-project-name admin \
--os-user-domain-name Default \
--os-project-domain-name Default \
--os-auth-url {{ os_auth_url }} \
--os-identity-api-version 3 \
| grep service)

if [[ $project_test != '' ]]; then
  echo 'Existing service project detected...skipping creation...'
  echo $project_test
else
  openstack project create --domain default --description "Service Project" service \
  --os-username {{ os_username }} \
  --os-password {{ os_password }} \
  --os-project-name {{ os_project_name }} \
  --os-user-domain-name {{ os_user_domain_name }} \
  --os-project-domain-name {{ os_project_domain_name }} \
  --os-auth-url {{ os_auth_url }} \
  --os-identity-api-version {{ os_identity_api_version }}
fi

user_role_test=$(openstack role list \
--os-username {{ os_username }} \
--os-password {{ os_password }} \
--os-project-name {{ os_project_name }} \
--os-user-domain-name {{ os_user_domain_name }} \
--os-project-domain-name {{ os_project_domain_name }} \
--os-auth-url {{ os_auth_url }} \
--os-identity-api-version {{ os_identity_api_version }} \
| grep user)

if [[ $user_role_test != '' ]]; then
  echo 'Existing user role detected...skipping creation...'
  echo $user_role_test
else
  openstack role create user \
  --os-username {{ os_username }} \
  --os-password {{ os_password }} \
  --os-project-name {{ os_project_name }} \
  --os-user-domain-name {{ os_user_domain_name }} \
  --os-project-domain-name {{ os_project_domain_name }} \
  --os-auth-url {{ os_auth_url }} \
  --os-identity-api-version {{ os_identity_api_version }}
fi

service_user_test=$(openstack user list \
--os-username {{ os_username }} \
--os-password {{ os_password }} \
--os-project-name {{ os_project_name }} \
--os-user-domain-name {{ os_user_domain_name }} \
--os-project-domain-name {{ os_project_domain_name }} \
--os-auth-url {{ os_auth_url }} \
--os-identity-api-version {{ os_identity_api_version }} \
| grep keystone)

if [[ $service_user_test != '' ]]; then
  echo 'Existing keystone service user detected...skipping creation...'
  echo $service_user_test
else
openstack user create --domain default --password {{ keystone_service_password }} keystone \
--os-username {{ os_username }} \
--os-password {{ os_password }} \
--os-project-name {{ os_project_name }} \
--os-user-domain-name {{ os_user_domain_name }} \
--os-project-domain-name {{ os_project_domain_name }} \
--os-auth-url {{ os_auth_url }} \
--os-identity-api-version {{ os_identity_api_version }}

openstack role add --project service --user keystone admin \
--os-username {{ os_username }} \
--os-password {{ os_password }} \
--os-project-name {{ os_project_name }} \
--os-user-domain-name {{ os_user_domain_name }} \
--os-project-domain-name {{ os_project_domain_name }} \
--os-auth-url {{ os_auth_url }} \
--os-identity-api-version {{ os_identity_api_version }}
fi

ipa_domain_test=$(openstack domain list \
--os-username {{ os_username }} \
--os-password {{ os_password }} \
--os-project-name {{ os_project_name }} \
--os-user-domain-name {{ os_user_domain_name }} \
--os-project-domain-name {{ os_project_domain_name }} \
--os-auth-url {{ os_auth_url }} \
--os-identity-api-version {{ os_identity_api_version }} \
| grep "IPA Domain")

if [[ $ipa_domain_test != '' ]]; then
  echo 'Existing ipa domain detected...skipping creation...'
  echo $ipa_domain_test
else
  openstack domain create --description "IPA Domain" ipa \
  --os-username {{ os_username }} \
  --os-password {{ os_password }} \
  --os-project-name {{ os_project_name }} \
  --os-user-domain-name {{ os_user_domain_name }} \
  --os-project-domain-name {{ os_project_domain_name }} \
  --os-auth-url {{ os_auth_url }} \
  --os-identity-api-version {{ os_identity_api_version }}
fi
