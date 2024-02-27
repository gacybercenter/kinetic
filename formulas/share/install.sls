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
 #  - /formulas/common/ceph/repo

share_packages:
  pkg.installed:
    - pkgs:
      - manila-share
      - python3-pymysql
      - python3-openstackclient
      - python3-manilaclient
      - python3-memcache
      - ceph-common
      - python3-rbd
      - python3-rados
      - nfs-ganesha
      - nfs-ganesha-ceph
      - python3-cephfs
      - sqlite3
      - python3-etcd3gw

share_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - python-manilaclient
      - memcache
      - pymysql
      - etcd3gw

salt-pip_installs:
  pip.installed:
    - bin-env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - pymysql
      - python-openstackclient
      - python-manilaclient
      - memcache
      - etcd3gw
    - require:
      - pip: share_pip
