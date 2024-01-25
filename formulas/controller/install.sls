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

controller_packages:
  pkg.installed:
    - pkgs:
      - qemu-system-x86
      - genisoimage
      - mdadm
      - xfsprogs
      - haveged
      - python3-libvirt
      - libvirt-dev
      - libguestfs-tools
    - reload_modules: true

controller_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - libvirt-python

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - names:
      - libvirt-python
    - require:
      - pip: controller_pip

{% if grains['os_family'] == 'Debian' %}

controller_packages_deb:
  pkg.installed:
    - pkgs:
      - libvirt-clients
      - libvirt-daemon-system
      - qemu-utils
    - reload_modules: true

{% elif grains['os_family'] == 'RedHat' %}

controller_packages_rpm:
  pkg.installed:
    - pkgs:
      - libvirt-client
      - libvirt-daemon-kvm
    - reload_modules: true

{% endif %}
