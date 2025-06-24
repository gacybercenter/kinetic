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
pyroute2_patch:
  file.managed:
    - makedirs: True
    - names:
      - /opt/saltstack/salt/extras-3.10/pyroute2/ndb/compat.py:
        - source: salt://formulas/common/pyroute2/compat.py
      - /usr/local/lib/python3.10/dist-packages/pyroute2/ndb/compat.py:
        - source: salt://formulas/common/pyroute2/compat.py
    - require:
      - pip: pyroute2_salt_pip
###

## This state doesn't apply to salt/pxe past this point

## disable unneeded services and enable needed ones
##


### The stub resolver is causing bizarre issues and
### intermittently returning publicly routable addresses
### for hosts statically defined on the DNS server
### This symlink points at the full resolver
### You should only do this with versions of systemd
### 241 or greater

/etc/resolv.conf:
  file.symlink:
    - target: /run/systemd/resolve/resolv.conf
    - force: True

{% for network in pillar['hosts'][grains['type']]['networks'] if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':managed', True) == True %}
  {% set subnet_cidr = pillar['networking']['subnets'][network] %}
  {% set cidr_prefix = subnet_cidr.split('/')[1] %}
  {% set netmask_result = salt['network_utils.cidr_to_netmask'](cidr_prefix) %}
  {% set netmask = netmask_result['netmask'] if netmask_result['success'] else '255.255.255.0' %}
  {% set base_ip = subnet_cidr.split('.0/')[0] %}
  {% set host_id = pillar['bmh'][grains['id']]['network']['management_ip'].split('.')[3] %}
  {% set ip_address = base_ip ~ '.' ~ host_id %}
  {% set interface = pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] %}

{{ interface }}:
  network.managed:
    - enabled: True
    - type: eth
  {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':bridge', False) == True %}
    - proto: manual
    - bridge: {{ network }}_br
  {% else %}
    - proto: static
    - ipaddr: {{ ip_address }}
    - netmask: {{ netmask }}
    - dns:
        - {{ pillar['dhcp-options']['dns'] }}
    {% if network == 'management' %}
    - gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
    {% endif %}
  {% endif %}
    {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':bridge', False) == True %}
{{ network }}_br:
  network.managed:
    - enabled: True
    - proto: static
    - type: bridge
    - bridge: {{ network }}_br
    - delay: 0
    - ports: {{ interface }}
    - ipaddr: {{ ip_address }}
    - netmask: {{ netmask }}
    - dns:
        - {{ pillar['dhcp-options']['dns'] }}
      {% if network == 'management' %}
    - gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
    - use:
      - network: {{ interface }}
    - require:
      - network: {{ interface }}
      {% endif %}
    {% endif %}
{% endfor %}