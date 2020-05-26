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
  {% if network == 'management' %}

/etc/systemd/network/{{ network }}.network:
  file.managed:
    - contents: |
        [Match]
        Name={{ pillar[srv][grains['type']]['networks']['interfaces'][network]['interface'] }}

        [Network]
        DHCP=yes
  {% else %}


  {% endif %}
{% endfor %}

whatever:
  module.run:
    - name: address.client_get_address
    - m_username: api
    - m_password: {{ pillar['api']['user_password'] }}
