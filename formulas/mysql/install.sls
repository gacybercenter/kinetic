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
  - /formulas/common/mariadb/repo

mariadb_packages:
  pkg.installed:
    - pkgs:
      - mariadb-server
      - python3-pymysql
    - reload_modules: True

pymysql_pip:
  pip.installed:
    - name: pymysql
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - name: pymysql
    - require:
      - pip: pymysql_pip