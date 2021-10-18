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

held_packages:
  pkg.installed:
    - pkgs:
      - nova-api: 3:23.0.2-0ubuntu1~cloud0
      - nova-conductor: 3:23.0.2-0ubuntu1~cloud0
      - nova-spiceproxy: 3:23.0.2-0ubuntu1~cloud0
      - nova-scheduler: 3:23.0.2-0ubuntu1~cloud0
    - hold: True

nova_packages:
  pkg.installed:
    - pkgs:     
      - python3-openstackclient
      - python3-etcd3gw

{% elif grains['os_family'] == 'RedHat' %}

nova_packages:
  pkg.installed:
    - pkgs:
      - openstack-nova-api
      - openstack-nova-conductor
      - openstack-nova-spicehtml5proxy
      - openstack-nova-scheduler
      - python3-openstackclient
      - git

{% endif %}
