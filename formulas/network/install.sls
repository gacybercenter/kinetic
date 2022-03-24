## Copyright 2019 Augusta University
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

include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}

network_packages:
  pkg.installed:
    - pkgs:
      - neutron-plugin-ml2
      - neutron-linuxbridge-agent
      - neutron-l3-agent
      - neutron-dhcp-agent
      - neutron-metadata-agent
      - python3-openstackclient
      - python3-tornado
      - python3-etcd3gw

  {% elif pillar['neutron']['backend'] == "openvswitch" %}

network_packages:
  pkg.installed:
    - pkgs:
      - neutron-plugin-ml2
      - neutron-openvswitch-agent
      - neutron-l3-agent
      - neutron-dhcp-agent
      - neutron-metadata-agent
      - python3-openstackclient
      - python3-tornado
    {% if salt['pillar.get']('hosts:octavia:enabled', False) == True %}
      - redis
      - octavia-health-manager
      - octavia-housekeeping
      - octavia-worker
      - python3-octavia
      - python3-octaviaclient
    {% endif %}
  {% endif %}

{% elif grains['os_family'] == 'RedHat' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}

network_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron
      - openstack-neutron-ml2
      - openstack-neutron-linuxbridge
      - iptables-ebtables
      - python3-openstackclient

  {% elif pillar['neutron']['backend'] == "openvswitch" %}

network_packages:
  pkg.installed:
    - pkgs:
      - openstack-neutron
      - openstack-neutron-ml2
      - openstack-neutron-openvswitch
      - iptables-ebtables
      - python3-openstackclient
    {% if salt['pillar.get']('hosts:octavia:enabled', False) == True %}
      - openstack-octavia-health-manager
      - openstack-octavia-housekeeping
      - openstack-octavia-worker
      - python3-octavia
      - python3-octaviaclient
    {% endif %}
  {% endif %}
{% endif %}
