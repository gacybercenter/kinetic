## Set custom ifwatch grain that contains list of interfaces that I want to monitor with the network
## beacon

## TODO - make pillar target align with grain value to avoid this
{% if grains['virtual'] == 'physical' %}
  {% set srv = 'hosts' %}
{% else %}
  {% set srv = 'virtual' %}
{% endif %}

ifwatch:
  grains.present:
    - value:
{% for interface in pillar[srv][grains['type']]['networks']['interfaces'] %}
      - {{ interface }}
{% endfor %}

NetworkManager:
  service.disabled

systemd-resolved:
  service.enabled

systemd-networkd:
  service.enabled
