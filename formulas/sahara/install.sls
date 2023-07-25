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

sahara_packages:
  pkg.installed:
    - pkgs:
      - apache2
      - sahara
      - sahara-api
      - sahara-engine
      - python3-saharaclient
      - python3-openstackclient
      - python3-etcd3gw

openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

saharaclient_pip:
  pip.installed:
    - name: python-saharaclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

etcd3gw_pip:
  pip.installed:
    - name: etcd3gw
    - bin_env: 'usr/bin/pip3'
    - reload_modules: True

sahara_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -python-saharaclient
      -python-openstackclient
      -etcd3gw
    -require:
      -sahara_packages

{% elif grains['os_family'] == 'RedHat' %}

sahara_packages:
  pkg.installed:
    - pkgs:
      - openstack-sahara-api
      - openstack-sahara-engine
      - openstack-sahara
      - python3-saharaclient
      - python3-openstackclient

openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

sarahaclient_pip:
  pip.installed:
    - name: python-sarahaclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

sahara_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -python-saharaclient
      -python-openstackclient
    -require:
      -sahara_packages

{% endif %}
