## Copyright 2021 United States Army Cyber School
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
  - /formulas/compute/install

{% if pillar['gpu']['backend'] == "cyborg" %}
cyborg_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - python3-memcache
      - python3-pymysql
      - dkms
      - python3-etcd3gw
      - xorg-dev
      - libvulkan1
    - refresh: true

gpu_pips:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - pymysql_sa
      - eventlet
      - python-cyborgclient
      - memcache
      - python-openstackclient
      - pymysql

salt-pip-gpu_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - memcache
      - pymysql
      - etcd3gw
      - eventlet
    - require:
      - pip: gpu_pips

{% endif %}
