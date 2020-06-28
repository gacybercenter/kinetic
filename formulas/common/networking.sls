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
{% for interface in pillar[srv][grains['type']]['networks'] %}
      - {{ pillar[srv][grains['type']]['networks'][interface]['interfaces'][0] }}
{% endfor %}
###

## disable unneeded services and enable needed ones
##
netplan.io:
  pkg.removed

/etc/netplan:
  file.absent

/run/systemd/network:
  file.absent

NetworkManager:
  service.disabled

### The sub resolver is causing bizarre issues and
### intermittently returning publicly routable addresses
### for hosts statically defined on the DNS server
### This symlink points at the full resolver
/etc/resolv.conf:
  file.symlink:
    - target: /run/systemd/resolve/resolv.conf
    - force: True

systemd-resolved:
  service.enabled

systemd-networkd.socket:
  service.enabled

systemd-networkd:
  service.enabled

###

### Iterate through all networks
### Management is always DHCP
### Public is left up, but unconfigured`
### Private, sfe, and sbe are assigned addresses from the sqlite db
{% for network in pillar[srv][grains['type']]['networks'] %}

### There are three possible general configurations available:
### 1. Regular interface
### 2. Bonded interface
### 3. Bridged interface
### 4. Bonded and bridged interface


### Test for number of physical interfaces listed.  If >1, it is a bond and a netdev
### for the bond should be created.  This is separate and a prereq for any
### other types of netdevs (e.g. bridge)
  {% if salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
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
    {% for interface in salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':interfaces') %}
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
  {% if salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':bridge', False) == True %}
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
      {% if salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
        Name={{ network }}_bond
      {% else %}
        Name={{ pillar[srv][grains['type']]['networks'][network]['interfaces'][0] }}
      {% endif %}
        [Network]
        Bridge={{ network }}_br
  {% endif %}

  {% if network == 'management' %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - contents: |
        [Match]
    {% if salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':bridge', False) == True %}
        Name={{ network }}_br
    {% elif salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
        Name={{ network }}_bond
    {% else %}
        Name={{ pillar[srv][grains['type']]['networks'][network]['interfaces'][0] }}
    {% endif %}
        [Network]
        DHCP=yes

  {% elif network =='public' %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - contents: |
        [Match]
    {% if salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':bridge', False) == True %}
        Name={{ network }}_br
    {% elif salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
        Name={{ network }}_bond
    {% else %}
        Name={{ pillar[srv][grains['type']]['networks'][network]['interfaces'][0] }}
    {% endif %}
        [Network]
        DHCP=no

  {% else %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - replace: False
    - contents: |
        [Match]
    {% if salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':bridge', False) == True %}
        Name={{ network }}_br
    {% elif salt['pillar.get'](srv+':'+grains['type']+':networks:'+network+':interfaces') | length > 1 %}
        Name={{ network }}_bond
    {% else %}
        Name={{ pillar[srv][grains['type']]['networks'][network]['interfaces'][0] }}
    {% endif %}
        [Network]
        DHCP=no
        Address={{ salt['address.client_get_address']('api', pillar['api']['user_password'], network, grains['host']) }}/{{ pillar['networking']['subnets'][network].split('/')[1] }}

  {% endif %}
{% endfor %}
