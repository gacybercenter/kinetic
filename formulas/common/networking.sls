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

{% for network in pillar[srv][grains['type']]['networks']['interfaces'] %}
  {% if pillar[srv][grains['type']]['networks']['interfaces'][network]['bridge'] == True %}
/etc/systemd/network/{{ network }}.netdev:
  file.managed:
    - contents: |
        [NetDev]
        Name={{ network }}_br
        Kind=bridge

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interface'] }}

        [Network]
        Bridge={{ network }}_br

    {% if network == 'management' %}
/etc/systemd/network/{{ network }}_br.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ network }}_br

        [Network]
        DHCP=yes

    {% elif network =='public' %}

do nothing:
  test.nop

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
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interface'] }}

        [Network]
        DHCP=yes

    {% elif network =='public' %}

do nothing:
  test.nop

    {% else %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - replace: False
    - contents: |
        [Match]
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interface'] }}

        [Network]
        DHCP=no
        Address={{ salt['address.client_get_address']('api', pillar['api']['user_password'], network, grains['host']) }}/{{ pillar['networking']['subnets'][network].split('/')[1] }}

    {% endif %}
  {% endif %}
{% endfor %}
