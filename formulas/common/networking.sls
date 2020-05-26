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

test_{{ network }}:
  file.managed:
    - name: /root/test
    - contents: __slot__:salt:address.client_get_address(api, {{ pillar['api']['user_password'] }}, {{ network }}, foobar)
  {% endif %}
{% endfor %}
