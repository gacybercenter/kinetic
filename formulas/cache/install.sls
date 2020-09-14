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
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

cache_packages:
  pkg.installed:
    - pkgs:
      - podman
      - httpd
      - buildah
    - reload_modules: True

{% endif %}

pyinotify:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
