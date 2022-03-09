#!/bin/bash
export OS_USERNAME=octavia
export OS_PASSWORD={{ octavia_password }}
export OS_PROJECT_NAME=octavia
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ keystone_internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

set -ex

mgmt_port_id=$(openstack port create --security-group lb-health-mgr-sec-grp --device-owner Octavia:health-mgr --host=$(hostname) -c id -f value --network lb-mgmt-net $port_fixed_ip octavia-health-manager-listen-port)
netid=$(openstack network show lb-mgmt-net -c id -f value)

mgmt_port_mac=$(openstack port show -c mac_address -f value $mgmt_port_id)
brname=brq$(echo $netid|cut -c 1-11)

if [ "$1" == "start" ]; then
  ip link add o-hm0 type veth peer name o-bhm0
  brctl addif $brname o-bhm0
  ip link set o-bhm0 up
  ip link set dev o-hm0 address $mgmt_port_mac
  ip link set o-hm0 up
  iptables -I INPUT -i o-hm0 -p udp --dport 5555 -j ACCEPT
elif [ "$1" == "stop" ]; then
  ip link del o-hm0
else
  brctl show $brname
  ip a s dev o-hm0
fi