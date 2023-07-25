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

cinder_packages:
  pkg.installed:
    - pkgs:
      - cinder-api
      - cinder-scheduler
      - python3-openstackclient
      - python3-memcache
      - python3-etcd3gw

cinder_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: True
    -pkgs:
      -python-openstackclient
      -memcache
      -etcd3gw
    -require:
      -cinder_packages

openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

memcache_pip:
  pip.installed:
    - name: memcache
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

etcd3gw_pip:
  pip.installed:
    - name: etcd3gw
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

cinder_packages:
  pkg.installed:
    - pkgs:
      - openstack-cinder
      - python3-openstackclient
      - python3-memcached

openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

memcached_pip:
  pip.installed:
    - name: python-memcached
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

cinder_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: True
    -pkgs:
      -python-openstackclient
      -python-memcached
    -require:
      -cinder_packages

{% endif %}