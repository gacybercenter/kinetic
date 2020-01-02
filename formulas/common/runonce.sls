## Netplan.io is neat, but it only exists in Ubuntu 18.04 which isn't useful
## Revisit this if/when it gets more attention
## ifupdown is fully supported/developed upstream
netplan.io:
  pkg.removed

/etc/netplan:
  file.directory:
    - clean: true

{% if grains['os_family'] == 'Debian' %}
ifupdown:
  pkg.installed:
    - reload_modules: true
{% endif %}

ens3:
  network.managed:
    - enabled: true
    - type: eth
    - proto: dhcp
