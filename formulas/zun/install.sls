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

zun_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - python3-memcache
      - numactl
      - python3-pymysql
      - python3-etcd3gw

zun_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - pymysql
      - pymysql_sa
      - memcache
      - python-openstackclient
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - pymysql
      - pymysql_sa
      - memcache
      - python-openstackclient
      - etcd3gw
    - require:
      - pip: zun_pip

zun:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/zun
    - system: True
    - groups:
      - zun

/etc/zun:
  file.directory:
    - user: zun
    - group: zun
    - mode: "0755"
    - makedirs: True

/etc/zun/rootwrap.d:
  file.directory:
    - user: root
    - group: root
    - makedirs: True

git_config:
  cmd.run:
    - name: git config --system --add safe.directory "/var/lib/zun"
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

zun_latest:
  git.latest:
    - name: https://git.openstack.org/openstack/zun.git
    - branch: stable/{{ pillar['openstack']['version'] }}
    - target: /var/lib/zun
    - force_clone: true
    - require:
      - cmd: git_config

zun_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/zun/requirements.txt
    - unless:
      - systemctl is-active zun-api
    - require:
      - git: zun_latest

installzun:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/zun/
    - unless:
      - systemctl is-active zun-api
    - require:
      - cmd: zun_requirements
