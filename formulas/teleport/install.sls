include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

{% if grains['os_family'] == 'Debian' %}

teleport_packages:
  pkg.installed:
    - sources:
      - teleport: https://get.gravitational.com/teleport_4.3.5_amd64.deb

{% elif grains['os_family'] == 'RedHat' %}

teleport_packages:
  pkg.installed:
    - sources:
      - teleport: https://get.gravitational.com/teleport-4.3.5-1.x86_64.rpm

{% endif %}
