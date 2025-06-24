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



### Test for number of physical interfaces listed.  If >1, it is a bond and a netdev
### for the bond should be created.  This is separate and a prereq for any
### other types of netdevs (e.g. bridge)
    {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
dd/etc/systemd/network/{{ network }}_bond.netdev:
  file.managed:
    - contents: |
        [NetDev]
        Name={{ network }}_bond
        Kind=bond
        [Bond]
        Mode=802.3ad
        MIIMonitorSec=100ms

### For every physical interface that is supposed to be part of the bond,
### create a network file that associates it accordingly
      {% for interface in salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':interfaces') %}
/etc/systemd/network/{{ interface }}_bond.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ interface }}
        [Network]
        Bond={{ network }}_bond
      {% endfor %}
    {% endif %}

### If the interface is a bridge, there are three different files
### That need to be created
### 1. a .netdev file creating the bridged interface object
### 2. a .network file associating the physical interface with the bridged interface object
### 3. a .network file configuring the bridge with address(es)
###
### 1. Create netdev
    {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':bridge', False) == True %}
/etc/systemd/network/{{ network }}_br.netdev:
  file.managed:
    - contents: |
        [NetDev]
        Name={{ network }}_br
        Kind=bridge

### Associate bridge netdev with physical interface (it could either be an individual interface,
### or a bond that was created above)
/etc/systemd/network/{{ network }}_br.network:
  file.managed:
    - contents: |
        [Match]
        {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
        Name={{ network }}_bond
        {% else %}
        Name={{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}
        {% endif %}
        [Network]
        Bridge={{ network }}_br
    {% endif %}
{% set prefix = {{ pillar['networking']['subnets'][network].split("/")[1] }} %}
{{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}:
  network.managed:
    - enabled: true
    - type: eth
    - proto: static
    - ip: {{ pillar['bmh'][grains['id']['ip']] }}
    - netmask: {% salt['network_utils.cidr_to_netmask'](prefix | '255.255.255.0') %}
    - dns: {{ pillar['dhcp-options']['dns'] }}
{% endfor %}
