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

cinder_packages:
  pkg.installed:
    - pkgs:
      - cinder-api
      - cinder-scheduler
      - python3-openstackclient
      - python3-memcache

{% elif grains['os_family'] == 'RedHat' %}

cinder_packages:
  pkg.installed:
    - pkgs:
      - openstack-cinder
      - python3-openstackclient
      - python3-memcached

{% endif %}
#This is designed to patch bug https://bugs.launchpad.net/cinder/+bug/1931004 and issue: https://git.cybbh.space/vta/kinetic/-/issues/70. As of July 29, 2021 this fix is still in progress upstream
#but works when tested in vtadev. This is a temporary solution pending a proper solution to code upstream.

rbd_patch:
  file.managed:
    - user: root
    - group: root
    - mode: '0644'
    - replace: True
    - names:
      - /usr/lib/python3/dist-packages/cinder/volume/drivers/rbd.py:
        - source: salt://formulas/cinder/files/rbd.py
      - /usr/lib/python3/dist-packages/cinder/tests/unit/volume/drivers/test_rbd.py:
        - source: salt://formulas/cinder/files/test_rbd.py