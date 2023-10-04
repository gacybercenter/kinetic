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

swift_packages:
  pkg.installed:
    - pkgs:
      - radosgw
      - python3-openstackclient
      - python3-etcd3gw

swift_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - python-openstackclient
      - etcd3gwes: True

salt-pip_installs:
  pip.installed:
    bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
      - etcd3gw
    - require:
      - pip: swift_pip

{% elif grains['os_family'] == 'RedHat' %}

swift_packages:
  pkg.installed:
    - pkgs:
      - ceph-radosgw
      - python3-openstackclient

swift_pip:
  pip.installed:
    - name: python-openstackclient
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

salt-pip_installs:
  pip.installed:
    bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - python-openstackclient
    - require:
      - pip: swift_pip

{% endif %}
