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

glance_packages:
  pkg.installed:
    - pkgs:
      - glance
      - python3-memcache
      - python3-rbd
      - python3-rados
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

glance_packages:
  pkg.installed:
    - pkgs:
      - openstack-glance
      - python3-memcached
      - python3-rbd
      - python3-rados
      - python3-openstackclient

{% endif %}

tqdm:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

image_bakery_latest:
  git.latest:
    - name: https://github.com/GeorgiaCyber/image-bakery.git
    - target: /tmp/image_bakery