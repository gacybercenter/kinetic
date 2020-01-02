#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

keystone-manage db_sync
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap --bootstrap-password {{ admin_password }} \
  --bootstrap-admin-url {{ admin_endpoint }} \
  --bootstrap-internal-url {{ internal_endpoint }} \
  --bootstrap-public-url {{ public_endpoint }} \
  --bootstrap-region-id RegionOne
