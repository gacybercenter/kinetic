## Copyright 2020 Augusta University
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

{% if grains['os_family'] == 'Debian' %}

nodesource:
  pkgrepo.managed:
    - humanname: nodesoure node.js 12.x repo
    - name: deb https://deb.nodesource.com/node_12.x focal main
    - file: /etc/apt/sources.list.d/nodejs.12.list
    - key_url: https://deb.nodesource.com/gpgkey/nodesource.gpg.key

{% elif grains['os_family'] == 'RedHat' %}

nodesource:
  pkgrepo.managed:
    - name: nodesource
    - baseurl: https://rpm.nodesource.com/pub_12.x/el/8/x86_64/
    - file: /etc/yum.repos.d/nodesource.repo
    - gpgkey: https://rpm.nodesource.com/pub/el/NODESOURCE-GPG-SIGNING-KEY-EL

{% endif %}

update_packages_node:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: nodesource
    - dist_upgrade: True

webssh2_packages:
  pkg.installed:
    - pkgs:
      - nodejs
      - git
{% if grains['os_family'] == 'RedHat' %}
      - policycoreutils-python-utils
      - policycoreutils
{% endif %}      
    - reload_modules: True

webssh2_source:
  git.latest:
    - name: https://github.com/billchurch/webssh2.git
    - target: /var/www/html/
    - rev: 0.3.0

install_webssh2:
  cmd.run:
    - name: npm install --production && npm audit fix
    - cwd: /var/www/html/app
    - creates:
      - /var/www/html/app/node_modules
