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

heat_packages:
  pkg.installed:
    - pkgs:
      - heat-api
      - heat-api-cfn
      - heat-engine
      - python3-openstackclient
      - python3-tornado
      - python3-zunclient
      - python3-designateclient
      - python3-vitrageclient
      - python3-etcd3gw

heat_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true
    - names:
      - python-openstackclient
      - tornado
      - python-zunclient
      - python-designateclient
      - python-vitrageclient
      - etcd3gw
    - require:
      - pkg: heat_packages

heat_packages_salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - tornado
      - python-zunclient
      - python-designatedclient
      - python-vitrageclient
      - etcd3gw
    - require:
      - pkg: heat_pip

{% elif grains['os_family'] == 'RedHat' %}

heat_packages:
  pkg.installed:
    - pkgs:
      - openstack-heat-api
      - openstack-heat-api-cfn
      - openstack-heat-engine
      - python3-openstackclient
      - uwsgi-plugin-python3-tornado
      - python3-designateclient
      - python3-pip
    - reload_modules: true

heat_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true
    - names:
      - python-openstackclient
      - tornado
      - python-designateclient

heat_packages_salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - tornado
      - python-designatedclient
    - require:
      - pkg: heat_pip

{% endif %}
