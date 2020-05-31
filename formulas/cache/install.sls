{% if grains['os_family'] == 'Debian' %}
include:
  - formulas/docker/common/repo

cache_packages:
  pkg.installed:
    - pkgs:
      - containerd.io
      - python3-pip
      - docker-ce
      - apache2

docker:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

{% elif grains['os_family'] == 'RedHat' %}

cache_packages:
  pkg.installed:
    - pkgs:
      - podman
      - httpd

{% endif %}
