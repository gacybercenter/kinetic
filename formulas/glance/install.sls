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
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

glance_packages:
  pkg.installed:
    - pkgs:
      - glance
      - python3-memcache
      - python3-rbd
      - python3-rados
      - python3-openstackclient
      - python3-etcd3gw
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - name: boto3

glance_pip:
  pip.intalled:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - etcd3gw
      - memcache
      ##rbd and rados
    - require:
      - pkg: glance_packages

glance_packages_salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - python-openstackclient
      - etcd3gw
      - memcache
      ##rdb and rados
    -require:
      - pkg: glance_pip

{% elif grains['os_family'] == 'RedHat' %}

glance_packages:
  pkg.installed:
    - pkgs:
      - openstack-glance
      - python3-memcached
      - python3-rbd
      - python3-rados
      - python3-openstackclient
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - name: boto3

glance_pip:
  pip.intalled:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - python3-memcached
      ##rbd and rados

glance_packages_salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - python-openstackclient
      - python3-memcached
      ##rbd and rados
    -require:
      - pkg: glance_pip

{% endif %}
