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

keystone_packages:
  pkg.installed:
    - pkgs:
      - keystone
      - python3-ldap
      - python3-ldappool
      - python3-openstackclient
      - ldap-utils
      - apache2
      - libapache2-mod-wsgi-py3
      - python3-etcd3gw

ldap3_pip:
  pip.installed:
    - name: ldap3
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

ldappool_pip:
  pip.installed:
    - name: ldappool
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

etcd3gw_pip:
  pip.installed:
    - name: etcd3gw
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

shade_pip:
  pip.installed:
    - name: shade
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

keystone_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -shade
      -ldap3
      -ldappool
      -python-openstackclient
      -etcd3gw
    -requires:
      -keystone_packages

{% elif grains['os_family'] == 'RedHat' %}

keystone_packages:
  pkg.installed:
    - pkgs:
      - openstack-keystone
      - python3-ldap3 ## version agnostic
      - python3-openstackclient ## version agnostic
      - openldap-clients
      - httpd
      - python3-mod_wsgi

{% endif %}

shade:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

ldap3_pip:
  pip.installed:
    - name: ldap3
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

mod_wsgi_pip:
  pip.installed:
    - name: mod_wsgi
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

shade_pip:
  pip.installed:
    - name: shade
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

keystone_packages_salt_pip:
  pip.installed:
    -bin_env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -shade
      -ldap3
      -python-openstackclient
      -mod_wsgi
    -requires:
      -keystone_packages

## the shade module is affected by https://github.com/saltstack/salt/issues/24925
## this is an attempt at a workaround
Restart Salt Minion:
  cmd.run:
    - name: 'salt-call service.restart salt-minion'
    - bg: True
    - onchanges:
      - pip: shade
