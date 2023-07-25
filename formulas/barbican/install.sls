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

barbican_packages:
  pkg.installed:
    - pkgs:
      - barbican-api
      - barbican-keystone-listener
      - barbican-worker
      - python3-openstackclient
      - python3-etcd3gw

openstackclient_pip:
  pip.installed:
    - name: openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

etcd3gw_pip:
  pip.installed:
    - name: etcd3gw
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

barbican_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -openstackclient
      -etcd3gw
    -require:
      -barbican_packages

{% elif grains['os_family'] == 'RedHat' %}

barbican_packages:
  pkg.installed:
    - pkgs:
      - openstack-barbican
      - openstack-barbican-api
      - openstack-barbican-keystone-listener
      - openstack-barbican-worker
      - python3-openstackclient
      - httpd
      - python3-mod_wsgi

openstackclient_pip:
  pip.installed:
    - name: openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

mod_wsgi_pip:
  pip.installed:
    - name: mod_wsgi
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

barbican_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: True
    -pkgs:
      -python-openstackclient
      -mod_wsgi
    -require:
      -barbican_packages

{% endif %}
