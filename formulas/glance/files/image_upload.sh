#!/bin/bash

export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

if [ "$(openstack image list | grep {{ glance_name }}) -eq 0" ]; then
  {% if args['needs_conversion'] == true %}
    curl -s -L {{ remote_url }} -o image.qcow2
    qemu-img convert -f qcow2 image.qcow2 {{ glance_name }}.raw
    openstack image create {{ glance_name }}.raw --container-format bare --disk-format raw --public --protected
    rm image.qcow2
  {% else %}
    curl -s -L {{ remote_url }} | openstack image create {{ glance_name }} --container-format bare disk-format raw --public --protected
  {% endif %}
fi
