#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

public_test=$(openstack network list | grep public)

if [[ $public_test != '' ]]; then
  echo 'Existing public network detected...exiting...'
  exit
fi

openstack network create --external --share --provider-physical-network provider --provider-network-type flat public
openstack subnet create --network public --allocation-pool start={{ start }},end={{ end }} --dns-nameserver {{ dns }} --gateway {{ gateway }} --subnet-range {{ cidr }} public_subnet
