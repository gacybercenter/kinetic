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
  - /formulas/common/ceph/repo

{% if grains['os_family'] == 'Debian' %}

volume_packages:
  pkg.installed:
    - pkgs:
      - python3-openstackclient
      - cinder-volume
      - python3-memcache
      - ceph-common
      - python3-rbd
      - python3-rados

{% elif grains['os_family'] == 'RedHat' %}

volume_packages:
  pkg.installed:
    - pkgs:
      - openstack-cinder
      - python3-openstackclient
      - python3-memcached
      - ceph-common
      - python3-rbd
      - python3-rados

{% endif %}
