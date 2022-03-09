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

# public_test=$(openstack network list | grep public)

# if [[ $public_test != '' ]]; then
#   echo 'Existing public network detected...exiting...'
#   exit
# fi

openstack flavor create --id 200 --vcpus 1 --ram 1024 --disk 2 "amphora" --private

openstack security group create lb-mgmt-sec-grp
openstack security group rule create --protocol icmp lb-mgmt-sec-grp
openstack security group rule create --protocol tcp --dst-port 22 lb-mgmt-sec-grp
openstack security group rule create --protocol tcp --dst-port 9443 lb-mgmt-sec-grp
openstack security group create lb-health-mgr-sec-grp
openstack security group rule create --protocol udp --dst-port 5555 lb-health-mgr-sec-grp

octavia_mgmt_subnet={{ octavia_mgmt_subnet }}
octavia_mgmt_subnet_start={{ octavia_mgmt_subnet_start }}
octavia_mgmt_subnet_end={{ octavia_mgmt_subnet_end }}
octavia_mgmt_port_ip={{ octavia_mgmt_port_ip }}

openstack network create lb-mgmt-net
openstack subnet create --subnet-range $octavia_mgmt_subnet --allocation-pool start=$octavia_mgmt_subnet_start,end=$octavia_mgmt_subnet_end --network lb-mgmt-net lb-mgmt-subnet

subnet_id=$(openstack subnet show lb-mgmt-subnet -f value -c id)
port_fixed_ip="--fixed-ip subnet=$subnet_id,ip-address=$octavia_mgmt_port_ip"

mgmt_port_id=$(openstack port create --security-group lb-health-mgr-sec-grp --device-owner Octavia:health-mgr --host=$(hostname) -c id -f value --network lb-mgmt-net $port_fixed_ip octavia-health-manager-listen-port)

mgmt_port_mac=$(openstack port show -c mac_address -f value \
  $mgmt_port_id)

sudo ip link add o-hm0 type veth peer name o-bhm0
netid=$(openstack network show lb-mgmt-net -c id -f value)
brname=brq$(echo $netid|cut -c 1-11)
sudo brctl addif $brname o-bhm0
sudo ip link set o-bhm0 up

sudo ip link set dev o-hm0 address $mgmt_port_mac
sudo iptables -I INPUT -i o-hm0 -p udp --dport 5555 -j ACCEPT
sudo dhclient -v o-hm0 -cf /etc/dhcp/octavia





openstack network create --external --share --provider-physical-network provider --provider-network-type flat public
openstack subnet create --network public --allocation-pool start={{ start }},end={{ end }} --dns-nameserver {{ dns }} --gateway {{ gateway }} --subnet-range {{ cidr }} public_subnet
