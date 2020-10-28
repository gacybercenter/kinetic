## Copyright 2018 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

service_test=$(openstack service list | grep nova)
if [[ $service_test != '' ]]; then
  echo 'Existing nova service detected...exiting...'
  exit
fi

openstack user create --domain default --password {{ nova_service_password }} nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public {{ nova_public_endpoint }}
openstack endpoint create --region RegionOne compute internal {{ nova_internal_endpoint }}
openstack endpoint create --region RegionOne compute admin {{ nova_admin_endpoint }}
