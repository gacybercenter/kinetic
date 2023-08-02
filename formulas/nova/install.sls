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

nova_packages:
  pkg.installed:
    - pkgs:
      - nova-api
      - nova-conductor
      - nova-spiceproxy
      - nova-serialproxy
      - nova-scheduler
      - python3-openstackclient
      - python3-etcd3gw

nova_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - etcd3gw

nova_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -python-openstackclient
      -etcd3gw
    -require:
      -nova_pip

{% elif grains['os_family'] == 'RedHat' %}

nova_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-api
      - openstack-nova-conductor
      - openstack-nova-spicehtml5proxy
      - openstack-nova-scheduler
      - python3-openstackclient
      - git

nova_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

nova_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -python-openstackclient
    -require:
      -nova_pip

{% endif %}
