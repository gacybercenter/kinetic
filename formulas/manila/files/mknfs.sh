#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

nfs_test=$(manila type-list | grep nfs)

if [[ $nfs_test != '' ]]; then
  echo 'Existing manila nfs type detected...exiting...'
  exit
fi

manila type-create nfs false
manila type-key nfs set vendor_name=Ceph storage_protocol=NFS
