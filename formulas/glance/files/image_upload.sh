#!/bin/bash

export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

if [ "$(openstack image list | grep {{ glance_name }}) -eq 0" ]; then
  if {{ needs_conversion }} == true; then
    curl -s -L {{ remote_url }} -o image.qcow2 &&
    qemu-img convert -f qcow2 image.qcow2 {{ glance_name }}.raw &&
    openstack image create --file "{{ glance_name }}.raw" --container-format bare --disk-format raw --public --protected {{ glance_name }}
    rm image.qcow2
  else
    #glance image-create-via-import is experimental. Initial testing was successful
    glance image-create-via-import --import-method web-download --uri {{ remote_url }} --name {{ glance_name }} --container-format bare --disk-format raw --visibility public --protected True
  fi
fi
