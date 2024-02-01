## Copyright 2018 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  #- /formulas/common/docker/repo

{% if grains['os_family'] == 'Debian' %}

cache_packages:
  pkg.installed:
    - pkgs:
      - apt-cacher-ng
      - python3-pip
      - apache2
      - docker.io
      - docker-compose
      - containerd
    - reload_modules: True

## Install docker pip module version 5.0.3 due to bug in 6.0.0, as seen here related to saltstack
## https://github.com/saltstack/salt/issues/62602
cache_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - pkgs:
      - pyinotify
      - docker == 5.0.3
    - reload_modules: true
    - require:
      - pkg: cache_packages


salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - pkgs:
      - pyinotify
      - docker == 5.0.3
    - reload_modules: true
    - require:
      - pkg: cache_packages
      - pip: cache_pip

{% elif grains['os_family'] == 'RedHat' %}

cache_packages:
  pkg.installed:
    - pkgs:
      - podman
      - httpd
      - buildah
    - reload_modules: True

{% endif %}