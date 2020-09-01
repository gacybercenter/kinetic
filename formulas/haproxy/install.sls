include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  
haproxy_packages:
  pkg.installed:
    - pkgs:
      - haproxy
      - certbot

{% if grains['os_family'] == 'RedHat' %}

haproxy_packages_redhat:
  pkg.installed:
    - pkgs:
      - policycoreutils-python-utils
    - reload_modules: True

{% endif %}
