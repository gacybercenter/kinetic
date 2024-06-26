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
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - etcd3gw
      - boto3
    - require:
      - pkg: glance_packages

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: True
    - pkgs:
      - python-openstackclient
      - etcd3gw
    - require:
      - pip: glance_pip
