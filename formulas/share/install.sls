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

{% if grains['os_family'] == 'Debian' %}

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

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

manilaclient_pip:
  pip.installed:
    - name: python-manilaclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

memcache_pip:
  pip.installed:
    - name: memcache
    - bin_env: 'usr/bin/pip3'
    - reload_modules: True

pymysql_pip:
  pip.installed:
    - name: pymysql
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

etcd3gw_pip:
  pip.installed:
    - name: etcd3gw
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

share_packages_salt_pip:
  pip.installed: 
    bin-env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -pymysql
      -python-openstackclient
      -python-manilaclient
      -memcache
      -etcd3gw
      #cephfs, rbd, rados- pip install ?
    -require:
      -share_packages

{% elif grains['os_family'] == 'RedHat' %}

share_packages:
  pkg.installed:
    - pkgs:
      - openstack-manila-share
      - python3-PyMySQL
      - python3-openstackclient
      - python3-manilaclient
      - python3-memcached
      - centos-release-nfs-ganesha30
      - ceph-common
      - python3-rbd
      - python3-rados
    - reload_modules: true

ganesha_packages:
  pkg.installed:
    - pkgs:
      - nfs-ganesha
      - nfs-ganesha-ceph
      - nfs-ganesha-selinux
      - nfs-ganesha-rados-urls
      - nfs-ganesha-rados-grace
    - require:
      - pkg: share_packages

python-openstackclient_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

manilaclient_pip:
  pip.installed:
    - name: python-manilaclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

memcached_pip:
  pip.installed:
    - name: python-memcached
    - bin_env: 'usr/bin/pip3'
    - reload_modules: True

pymysql_pip:
  pip.installed:
    - name: pymysql
    - bin_env: '/usr/bin/pip3'
    -reload_modules: True

share_packages_salt_pip:
  pip.installed: 
    bin-env: '/usr/bin/salt-pip'
    -reload_modules: true
    -pkgs:
      -pymysql
      -python-openstackclient
      -python-manilaclient
      -python-memcached
      #rdb and rados - pip install ?
    -require:
      -share_packages

{% endif %}
