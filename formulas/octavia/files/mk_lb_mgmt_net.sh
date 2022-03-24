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
export OS_USERNAME=octavia
export OS_PASSWORD={{ octavia_password }}
export OS_PROJECT_NAME=octavia
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

octavia_net_test=$(openstack network list | grep lb-mgmt-net)

if [[ $octavia_net_test != '' ]]; then
  echo 'Existing octavia network detected...exiting...'
  exit
fi

openstack flavor create --id 200 --vcpus 1 --ram 1024 --disk 2 "amphora" --private

openstack security group create lb-mgmt-sec-grp
openstack security group rule create --protocol icmp lb-mgmt-sec-grp
openstack security group rule create --protocol tcp --dst-port 22 lb-mgmt-sec-grp
openstack security group rule create --protocol tcp --dst-port 9443 lb-mgmt-sec-grp
openstack security group create lb-health-mgr-sec-grp
openstack security group rule create --protocol udp --dst-port 5555 lb-health-mgr-sec-grp

openstack network create lb-mgmt-net
openstack subnet create --subnet-range {{ octavia_mgmt_subnet }} --allocation-pool start={{ octavia_mgmt_subnet_start }},end={{ octavia_mgmt_subnet_end }} --network lb-mgmt-net lb-mgmt-subnet
