## Common networking state.  This is complicated.  Read the inline comments.

## Currently, networking is handled differently depending on
## whether or not your a physical machine or a virtual one
## This will probably be merged at some point, but for now
## this piece just determines which lookup you need to do
## to get the rest of your network configuration

{% if grains['virtual'] == 'physical' %}
  {% set srv = 'hosts' %}
{% else %}
  {% set srv = 'virtual' %}
{% endif %}

## Set custom ifwatch grain that contains list of interfaces that I want to monitor with the network
## beacon
ifwatch:
  grains.present:
    - force: true
    - value:
{% for interface in pillar[srv][grains['type']]['networks']['interfaces'] %}
      - {{ interface }}
{% endfor %}

## Configure bond slaves, if any
{% if pillar[srv][grains['type']]['networks']['bonds'] != False %}
  {% for master in pillar[srv][grains['type']]['networks']['bonds'] %}
    {% for slave in pillar[srv][grains['type']]['networks']['bonds'][master] %}
{{ master }}_{{ slave }}:
  network.managed:
    - name: {{ slave }}
    - enabled: True
    - type: slave
    - master: {{ master }}
    {% endfor %}
  {% endfor %}
{% endif %}

## Get current management IP address.  This will be used to calculate the
## assigned addresses for all of the other networks.
{% set management_address_octets = salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0].split('.') %}

## Loop through all defined interfaces in the pillar for this particular device
{% for interface in pillar[srv][grains['type']]['networks']['interfaces'] %}
{% if pillar[srv][grains['type']]['networks']['interfaces'][interface]['bridge'] == True %}
bridge-utils_{{ interface }}:
  pkg.installed:
    - name: bridge-utils
    - reload_modules: True
{% endif %}
## Set short variable for easy reference
{% set current_network = pillar[srv][grains['type']]['networks']['interfaces'][interface]['network'] %}

## This piece creates the following variables for all system-wide networks:
## 1. Full network as the variable [subnet]_network (e.g. 1.2.3.0/24)
## 2. Network and subnet mask split as the variable [subnet]_network_split (e.g. [1.2.3.4, 24])
## 3. Python list of network octets as the variable [subnet]_netowkr_octets (e.g. [1,2,3,4]
## 4. Network mask as the variable [subnet]_network_netmask (e.g. 24)
{% set subnet_network = pillar['networking']['subnets'][current_network] %}
{% set subnet_network_split = subnet_network.split('/') %}
{% set subnet_network_octets = subnet_network_split[0].split('.') %}
{% set subnet_network_netmask = subnet_network_split[1] %}
{% set netmask = salt['network']['convert_cidr'](subnet_network)['netmask'] %}

## Actual state data starts here
## Physical interface definition
{{ interface }}:
  network.managed:
    - enabled: True
## adjust configuration based on whether or not interface is a bond
{% if salt['pillar.get'](''+srv+':'+grains['type']+':networks:interfaces:'+interface+':bond', False) == False %}
    - type: eth
{% else %}
    - type: bond
    - mode: 802.3ad
    - slaves: |-
          {%- for slave in salt['pillar.get']('srv:grains[type]:networks:bonds:interface') -%}
              {{ " "+slave }}
          {%- endfor %}
    - miimon: 100
    - downdelay: 200
    - lacp_rate: fast
{% endif %}
## If this interface is bridged, set appropriate state and master and
## companion interface
{% if pillar[srv][grains['type']]['networks']['interfaces'][interface]['bridge'] == True %}
  {% if grains['os_family'] == 'Debian' %}
    - proto: manual
  {% elif grains['os_family'] == 'RedHat' %}
    - proto: none
  {% endif %}
    - bridge: {{ current_network }}
## This is the companion interface if the interface is in bridge mode
## This won't exist on non-bridged devices
{{ current_network }}:
  network.managed:
    - enabled: true
    - type: bridge
{% if pillar[srv][grains['type']]['networks']['interfaces'][interface]['primary'] == True %}
## If working on the primary interface, it should be set to DHCP
## This is almost always going to be the management interface except in the
## case of haproxy, when it will be public
    - proto: dhcp
{% else %}
## Otherwise, calculate the IP address based on what management currently is.
  {% if grains['os_family'] == 'Debian' %}
    - proto: static
    - ipaddr: {{ subnet_network_octets[0] }}.{{ subnet_network_octets[1] }}.{{ management_address_octets[2] }}.{{ management_address_octets[3] }}/{{ subnet_network_netmask }}
  {% elif grains['os_family'] == 'RedHat' %}
    - proto: none
    - ipaddr: {{ subnet_network_octets[0] }}.{{ subnet_network_octets[1] }}.{{ management_address_octets[2] }}.{{ management_address_octets[3] }}
    - netmask: {{ netmask }}
  {% endif %}
{% endif %}
## bind bridged ports to their parents and set appropriate requisite
    - ports: {{ interface }}
    - require:
      - network: {{ interface }}
## If working on the primary interface, it should be set to DHCP
## This is almost always going to be the management interface except in the
## case of haproxy, when it will be public
{% elif pillar[srv][grains['type']]['networks']['interfaces'][interface]['primary'] == True %}
    - proto: dhcp
## Otherwise, calculate the IP address based on what management currently is.
{% else %}
  {% if grains['os_family'] == 'Debian' %}
    - proto: static
    - ipaddr: {{ subnet_network_octets[0] }}.{{ subnet_network_octets[1] }}.{{ management_address_octets[2] }}.{{ management_address_octets[3] }}/{{ subnet_network_netmask }}
  {% elif grains['os_family'] == 'RedHat' %}
    - proto: none
    - ipaddr: {{ subnet_network_octets[0] }}.{{ subnet_network_octets[1] }}.{{ management_address_octets[2] }}.{{ management_address_octets[3] }}
    - netmask: {{ netmask }}
  {% endif %}
{% endif %}
{% endfor %}
