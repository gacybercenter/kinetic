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

salt_pkgs:
  pkg.installed:
    - pkgs:
      - python3-tornado
      - salt-api
      - haveged
      - curl
      - python3-pygit2
    - reload_modules: True

salt_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - names:
      - cryptography
      - pyghmi
      - pygit2
      - tornado
      - redfish

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - pkgs:
      - cryptography
      - pyghmi
      - pygit2
      - tornado
      - redfish
    - reload_modules: true
    - require:
      - pkg: salt_pkgs