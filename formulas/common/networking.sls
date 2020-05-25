## Set custom ifwatch grain that contains list of interfaces that I want to monitor with the network
## beacon


ifwatch:
  grains.present:
    - value:
{% for interface in pillar[srv][grains['type']]['networks']['interfaces'] %}
      - {{ interface }}
{% endfor %}
