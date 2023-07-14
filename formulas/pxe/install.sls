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

pxe_packages:
  pkg.installed:
    - pkgs:
      - build-essential
      - python3-tornado
      - apache2
      - libapache2-mod-wsgi-py3
      - git
      - tftpd-hpa
    - reload_modules: True

pxe_pips:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - pkgs:
      - tornado
      - pyghmi
      - redfish
    - reload_modules: true
    - require:
      - pkg: pxe_packages

redfish_pip:
  pip.installed:
    - name: redfish
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

pyghmi_pip:
  pip.installed:
    - name: pyghmi
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
