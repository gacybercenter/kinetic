### TODO - make pillar target align with grain value to avoid this
{% if grains['virtual'] == 'physical' %}
  {% set srv = 'hosts' %}
{% else %}
  {% set srv = 'virtual' %}
{% endif %}


### Set custom ifwatch grain that contains list of interfaces that I want to monitor with the network
### beacon
ifwatch:
  grains.present:
    - value:
{% for interface in pillar[srv][grains['type']]['networks']['interfaces'] %}
      - {{ pillar[srv][grains['type']]['networks']['interfaces'][interface]['interface'] }}
{% endfor %}
###

### disable unneeded services and enable needed ones
###
NetworkManager:
  service.disabled

systemd-resolved:
  service.enabled

systemd-networkd:
  service.enabled
###

### Iterate through all networks
### Management is always DHCP
### Public is left up, but unconfigured`
### Private, sfe, and sbe are assigned addresses from the sqlite db
{% for network in pillar[srv][grains['type']]['networks']['interfaces'] %}
### If the interface is a bridge, there are three different files
### That need to be created
### 1. a .netdev file creating the bridged interface object
### 2. a .network file associating the physical interface with the bridged interface object
### 3. a .network file configuring the bridge with address(es)
###
### 1. Create netdev
  {% if salt['pillar.get'](srv+':'+grains['type']+':networks:interfaces:'+network+':bridge', False) == True %}
/etc/systemd/network/{{ network }}.netdev:
  file.managed:
    - contents: |
        [NetDev]
        Name={{ network }}_br
        Kind=bridge

### Associate bridge netdev with physical interface
/etc/systemd/network/{{ network }}.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interfaces'][0] }}

        [Network]
        Bridge={{ network }}_br

    {% if network == 'management' %}
### Configure interface
/etc/systemd/network/{{ network }}_br.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ network }}_br

        [Network]
        DHCP=yes

    {% elif network =='public' %}

/etc/systemd/network/{{ network }}_br.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ network }}_br

        [Network]
        DHCP=no

    {% else %}
/etc/systemd/network/{{ network }}_br.network:
  file.managed:
    - replace: False
    - contents: |
        [Match]
        Name={{ network }}_br

        [Network]
        DHCP=no
        Address={{ salt['address.client_get_address']('api', pillar['api']['user_password'], network, grains['host']) }}/{{ pillar['networking']['subnets'][network].split('/')[1] }}

    {% endif %}
  {% else %}

    {% if network == 'management' %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interfaces'][0] }}

        [Network]
        DHCP=yes

    {% elif network =='public' %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interfaces'][0] }}

        [Network]
        DHCP=no

    {% else %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - replace: False
    - contents: |
        [Match]
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interfaces'][0] }}

        [Network]
        DHCP=no
        Address={{ salt['address.client_get_address']('api', pillar['api']['user_password'], network, grains['host']) }}/{{ pillar['networking']['subnets'][network].split('/')[1] }}

    {% endif %}
  {% endif %}
{% endfor %}
