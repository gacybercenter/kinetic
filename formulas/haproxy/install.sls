haproxy:
  pkg.installed

{% if grains['os_family'] == 'Debian' %}

letsencrypt:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

haproxy_packages:
  pkg.installed:
    - pkgs:
      - certbot
      - policycoreutils-python-utils
    - reload_modules: True

{% endif %}
