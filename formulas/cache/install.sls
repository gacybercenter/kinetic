include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

{% if grains['os_family'] == 'Debian' %}

cache_packages:
  pkg.installed:
    - pkgs:
      - apt-cacher-ng
      - python3-pip
      - apache2

{% elif grains['os_family'] == 'RedHat' %}

cache_packages:
  pkg.installed:
    - pkgs:
      - podman
      - httpd
      - buildah

{% endif %}
