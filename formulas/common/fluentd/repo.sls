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

{% if grains['os_family'] == 'Debian' %}

fluentd_repo:
  pkgrepo.managed:
    - humanname: Treasure Data
    - name: deb https://packages.treasuredata.com/4/ubuntu/jammy jammy contrib
    - file: /etc/apt/sources.list.d/fluentd.list
    - key_url: https://packages.treasuredata.com/GPG-KEY-td-agent

update_packages_fluentd:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - fluentd_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}


{% endif %}