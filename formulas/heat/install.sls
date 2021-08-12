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

zunclient_install:
  pip.installed:
    - name: python-zunclient
    - bin_env: '/usr/bin/pip3'
    - require:
      - pkg: heat_packages
    - reload_modules: True

{% endif %}
