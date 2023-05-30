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
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo

{% if grains['os_family'] == 'Debian' %}

cyborg_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - python3-memcache
      - python3-pymysql
      - python3-etcd3gw

{% elif grains['os_family'] == 'RedHat' %}

cyborg_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - platform-python-devel
      - libffi-devel
      - gcc
      - gcc-c++
      - openssl-devel
      - python3-PyMySQL
      - python3-memcached
      - python3-openstackclient

{% endif %}

pymysql_sa:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

python-cyborgclient:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

cyborg:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/cyborg
    - system: True
    - groups:
      - cyborg

/etc/cyborg:
  file.directory:
    - user: cyborg
    - group: cyborg
    - mode: "0755"
    - makedirs: True

/var/log/cyborg:
  file.directory:
    - user: cyborg
    - group: adm
    - mode: "0755"
    - makedirs: True

git_config:
  cmd.run:
    - name: git config --system --add safe.directory "/var/lib/cyborg"
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

cyborg_latest:
  git.latest:
    - name: https://opendev.org/openstack/cyborg.git
    - branch: stable/2023.1
    - target: /var/lib/cyborg
    - force_clone: true
    - require:
      - cmd: git_config

cyborg_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/cyborg/requirements.txt
    - unless:
      - systemctl is-active cyborg-conductor
    - require:
      - git: cyborg_latest

installcyborg:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/cyborg/
    - unless:
      - systemctl is-active cyborg-conductor
    - require:
      - cmd: cyborg_requirements
