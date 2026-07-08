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

include:
  - /formulas/common/nftables/nftables

network_util:
  pkg.installed:
    - name: ifupdown
# netplan.io:
#   pkg.removed

/etc/netplan:
  file.absent

/run/systemd/network:
  file.absent
systemd-networkd.socket:
  service.disabled
systemd-networkd:
  service.disabled
NetworkManager:
  service.disabled

pin_salt_pip_version:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - names:
      - pip=={{ pillar['pip']['version'] }}

pyroute2_salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - pyroute2
      - pyroute2.ndb
      - pyroute2.ipdb
    - require:
      - pin_salt_pip_version

## Patch pyroute2 to fix a bug in the compat module until it is fixed upstream
## https://github.com/svinota/pyroute2/issues/1132
## https://github.com/svinota/pyroute2/pull/1133
## https://github.com/saltstack/salt/issues/65361
# pyroute2_patch:
#   file.managed:
#     - makedirs: True
#     - names:
#       - /opt/saltstack/salt/extras-3.10/pyroute2/ndb/compat.py:
#         - source: salt://formulas/common/pyroute2/compat.py
#       - /usr/local/lib/python3.10/dist-packages/pyroute2/ndb/compat.py:
#         - source: salt://formulas/common/pyroute2/compat.py
#     - require:
#       - pip: pyroute2_salt_pip
# ###

## This state doesn't apply to salt/pxe past this point

## disable unneeded services and enable needed ones
##


### The stub resolver is causing bizarre issues and
### intermittently returning publicly routable addresses
### for hosts statically defined on the DNS server
### This symlink points at the full resolver
### You should only do this with versions of systemd
### 241 or greater

# /etc/resolv.conf:
#   file.symlink:
#     - target: /run/systemd/resolve/resolv.conf
#     - force: True

{% for network in pillar['hosts'][grains['type']]['networks'] if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':managed', True) == True %}
  {% set subnet_cidr = pillar['networking']['subnets'][network] %}
  {% set cidr_prefix = subnet_cidr.split('/')[1] %}
  {% set netmask_result = salt['network_utils.cidr_to_netmask'](cidr_prefix) %}
  {% set netmask = netmask_result['netmask'] if netmask_result['success'] else '255.255.255.0' %}
  {% set base_ip = subnet_cidr.split('.0/')[0] %}
  {% set host_id = pillar['bmh'][grains['id']]['network']['management_ip'].split('.')[3] %}
  {% set ip_address = base_ip ~ '.' ~ host_id %}
  {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
    {% set iface1 = pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] %}
    {% set iface2 = pillar['hosts'][grains['type']]['networks'][network]['interfaces'][1] %}

{{ iface1 }}:
  network.managed:
    - enabled: True
    - type: slave
    - master: bond-{{ network }}

{{ iface2 }}:
  network.managed:
    - enabled: True
    - type: slave
    - master: bond-{{ network }}

bond-{{ network }}:
  network.managed:
    - enabled: True
    - type: bond
    - mode: 802.3ad
    - slaves: {{ iface1 }} {{ iface2 }}
    - mtu: 9000
    - dns:
        - {{ pillar['dhcp-options']['dns'] }}
    - require:
      - network: {{ iface1 }}
      - network: {{ iface2 }}

  {% if network == 'management' %}
    # Management bond gets the IP address
    - proto: static
    - ipaddr: {{ ip_address }}
    - netmask: {{ netmask }}
    - gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
  {% else %}
    # All other bonds have no IP - they become slaves to a bridge
    - proto: manual
    - bridge: {{ network }}_br
  {% endif %}

  # Enable promiscuous mode on bonds (required for many container networking scenarios)
promisc-bond-{{ network }}:
  cmd.run:
    - name: ip link set bond-{{ network }} promisc on
    - unless: ip -o link show bond-{{ network }} | grep -q PROMISC
    - require:
      - network: bond-{{ network }}

  {% else %}
    {% set interface = pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] %}

{{ interface }}:
  network.managed:
    - enabled: True
    - type: eth
    - mtu: 9000

  {% if network == 'management' %}
    # Only management interface gets an IP
    - proto: static
    - ipaddr: {{ ip_address }}
    - netmask: {{ netmask }}
    - dns:
        - {{ pillar['dhcp-options']['dns'] }}
    - gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
  {% else %}
    # All other interfaces become slaves to network-specific bridges (no IP)
    - proto: manual
    - bridge: {{ network }}_br
  {% endif %}

    # Create bridge for non-management networks (no IP on bridge)
    {% if network != 'management' %}
{{ network }}_br:
  network.managed:
    - enabled: True
    - type: bridge
    - proto: manual
    - mtu: 9000
    - delay: 0
    - ports: {{ interface }}
    - require:
      - network: {{ interface }}

    # Enable promiscuous mode on bridges (required for macvlan and container networking)
    promisc-bridge-{{ network }}:
      cmd.run:
        - name: ip link set {{ network }}_br promisc on
        - unless: ip -o link show {{ network }}_br | grep -q PROMISC
        - require:
          - network: {{ network }}_br
    {% endif %}

  {% endif %}
{% endfor %}
