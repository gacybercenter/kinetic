## Copyright 2021 United States Army Cyber School
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

jproxy_packages:
  pkg.installed:
    - pkgs:
      - python3-pip

jproxy_pip_packages:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true
    - names:
      - junos-eznc
      - jxmlease
      - yamlordereddictloader
      - pyOpenSSL