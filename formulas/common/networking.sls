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

### Set custom ifwatch grain that contains list of interfaces that I want to monitor with the network
### beacon
ifwatch:
  grains.present:
    - value:
{% if grains['type'] in ['salt','pxe'] %}
      - eth0
{% else %}
  {% for network in pillar['hosts'][grains['type']]['networks'] %}
      - {{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}
  {% endfor %}
{% endif %}
###

## This state doesn't apply to salt/pxe past this point
{% if grains['type'] not in ['salt', 'pxe'] %}

## disable unneeded services and enable needed ones
##
netplan.io:
  pkg.removed

install_pyroute2:
  pkg.installed:
    - name: python3-pyroute2

  {% if grains['os_family'] == 'RedHat' %}
install_networkd:
  pkg.installed:
    - pkgs:
      - systemd-networkd
  {% endif %}

/etc/netplan:
  file.absent

/run/systemd/network:
  file.absent

NetworkManager:
  service.disabled

systemd-resolved:
  service.enabled

systemd-networkd.socket:
  service.enabled

systemd-networkd:
  service.enabled

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

### Iterate through all networks
### Management is always DHCP
### Public is left up, but unconfigured`
### Private, sfe, and sbe are assigned addresses from the sqlite db
## Check if interface is managed, if so, execute the state.  If not, exit
  {% for network in pillar['hosts'][grains['type']]['networks'] if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':managed', True) == True %}

### There are four possible general configurations available:
### 1. Regular interface
### 2. Bonded interface
### 3. Bridged interface
### 4. Bonded and bridged interface


### Test for number of physical interfaces listed.  If >1, it is a bond and a netdev
### for the bond should be created.  This is separate and a prereq for any
### other types of netdevs (e.g. bridge)
    {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
/etc/systemd/network/{{ network }}_bond.netdev:
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

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - require:
      - file: /etc/resolv.conf
    - replace: True
    - contents: |
        [Match]
      {% if salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':bridge', False) == True %}
        Name={{ network }}_br
      {% elif salt['pillar.get']('hosts:'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
        Name={{ network }}_bond
      {% else %}
        Name={{ pillar['hosts'][grains['type']]['networks'][network]['interfaces'][0] }}
      {% endif %}
    {% if network == 'management' %}
        [Network]
        DHCP=yes
        KeepConfiguration=dhcp-on-stop
        [DHCPv4]
        SendRelease=false
    {% elif network =='public' %}
        [Network]
        DHCP=no
    {% else %}
        [Network]
        DHCP=no
        Address={{ salt['address.client_get_address']('api', pillar['api']['user_password'], network, grains['host']) }}/{{ pillar['networking']['subnets'][network].split('/')[1] }}
    {% endif %}
  {% endfor %}
{% endif %}
