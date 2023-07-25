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

designate_packages:
  pkg.installed:
    - pkgs:
      - bind9utils
      - designate
      - designate-worker
      - designate-producer
      - designate-mdns
      - python3-memcache
      - python3-designateclient
      - python3-openstackclient
      - python3-pip
      - python3-etcd3gw

pymemcache:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true
    - require:
      - pkg: designate_packages

designate_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -memcache
      -python-designateclient
      -python-openstackclient
      -etcd3gw
    -require:
      -designate_packages

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

python-designateclient_pip:
  pip.installed:
    - name: python-designateclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

ectd3gw_pip:
  pip.installed:
    - name: ectd3gw
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

designate_packages:
  pkg.installed:
    - pkgs:
      - bind
      - openstack-designate-api
      - openstack-designate-mdns
      - openstack-designate-producer
      - openstack-designate-worker
      - openstack-designate-central
      - python3-memcached
      - python3-designateclient
      - python3-openstackclient
      - python3-pymemcache

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

python-designateclient_pip:
  pip.installed:
    - name: python-designateclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

pymemcache_pip:
  pip.installed:
    - name: pymemcache
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

memcache_pip:
  pip.installed:
    - name: memcache
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

designate_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -memcache
      -python-designateclient
      -python-openstackclient
      -pymemcache
    -require:
      -designate_packages
{% endif %}
