include:
  - formulas/docker/common/repo

{% if grains['os_family'] == 'Debian' %}
apache2:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

httpd:
  pkg.installed
{% endif %}

cache_packages:
  pkg.installed:
    - pkgs:
      - containerd.io
      - python3-pip
      - docker-ce

docker:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true
