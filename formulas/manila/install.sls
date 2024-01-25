## Copyright 2019 Augusta University
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
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

manila_packages:
  pkg.installed:
    - pkgs:
      - manila-api
      - manila-scheduler
      - python3-openstackclient
      - python3-manilaclient
      - python3-memcache
      - python3-etcd3gw

manila_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - python-manilaclient
      - etcd3gw
      - memcache

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - python-manilaclient
      - memcache
      - etcd3gw
    - require:
      - pip: manila_pip

{% elif grains['os_family'] == 'RedHat' %}

manila_packages:
  pkg.installed:
    - pkgs:
      - openstack-manila
      - python3-openstackclient
      - python3-manilaclient
      - python3-memcached

manila_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - python-manilaclient
      - python-memcached

salt-pip_install:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - python-manilaclient
      - python-memcached
    - require:
      - pip: manila_pip

{% endif %}
