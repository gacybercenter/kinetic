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

{% if grains['os_family'] == 'Debian' %}

nodesource:
  pkgrepo.managed:
    - humanname: nodesoure node.js 12.x repo
    - name: deb https://deb.nodesource.com/node_12.x focal main
    - file: /etc/apt/sources.list.d/nodejs.12.list
    - key_url: https://deb.nodesource.com/gpgkey/nodesource.gpg.key

update_packages_node:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: nodesource
    - dist_upgrade: True

antora_packages:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - curl
      - lsb-release
      - gnupg
      - nodejs
      - apache2
    - reload_modules: True

{% elif grains['os_family'] == 'RedHat' %}

nodesource:
  pkgrepo.managed:
    - name: nodesource
    - baseurl: https://rpm.nodesource.com/pub_12.x/el/8/x86_64/
    - file: /etc/yum.repos.d/nodesource.repo
    - gpgkey: https://rpm.nodesource.com/pub/el/NODESOURCE-GPG-SIGNING-KEY-EL

update_packages_nodesource:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: nodesource

antora_packages:
  pkg.installed:
    - pkgs:
      - curl
      - gnupg2
      - nodejs
      - httpd
      - git
    - reload_modules: True

{% endif %}

### state.npm does an explicit match of versions, so minor updates from antora (e.g. 2.3.3) will
### not match 2.3, and salt will keep trying to install the same package over and over again.
### This is harmless, but ugly.  For now, drop versioning and always run latest.
### https://github.com/saltstack/salt/blob/master/salt/states/npm.py#L161
install_antora:
  npm.installed:
    - require:
      - pkg: antora_packages
    - pkgs:
      - "@antora/cli"
      - "@antora/site-generator-default"
