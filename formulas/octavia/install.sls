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

octavia_packages:
  pkg.installed:
    - pkgs:
      - bridge-utils
      - redis
      - octavia-api
      - python3-octavia
      - python3-octaviaclient
      - python3-memcache
      - python3-openstackclient
      - python3-pip
      - python3-etcd3gw

pymemcache:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true
    - require:
      - pkg: octavia_packages

{% elif grains['os_family'] == 'RedHat' %}

octavia_packages:
  pkg.installed:
    - pkgs:
      - bridge-utils
      - openstack-octavia-api
      - python3-octavia
      - python3-memcached
      - python3-octaviaclient
      - python3-openstackclient
      - python3-pymemcache

{% endif %}
