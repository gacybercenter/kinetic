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

mariadb_repo:
  pkgrepo.managed:
    - humanname: MariaDB 10.10
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "http://downloads.mariadb.com/MariaDB/mariadb-10.10/repo/ubuntu/" %}
    - name: deb [signed-by=/etc/apt/keyrings/MariaDB-Server-GPG-KEY arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
    {% endif %}
  {% endfor %}
{% else %}
    - name: deb [signed-by=/etc/apt/keyrings/MariaDB-Server-GPG-KEY arch=amd64] http://downloads.mariadb.com/MariaDB/mariadb-10.10/repo/ubuntu {{ pillar['ubuntu']['name'] }} main
{% endif %}
    - file: /etc/apt/sources.list.d/mariadb.list
    - key_url: https://supplychain.mariadb.com/MariaDB-Server-GPG-KEY
    - aptkey: False

mariadb_tools_repo:
  pkgrepo.managed:
    - humanname: MariaDB Tools
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "http://downloads.mariadb.com/Tools/ubuntu/" %}
    - name: deb [signed-by=/etc/apt/keyrings/MariaDB-Enterprise-GPG-KEY arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
    {% endif %}
  {% endfor %}
{% else %}
    - name: deb [signed-by=/etc/apt/keyrings/MariaDB-Enterprise-GPG-KEY arch=amd64] http://downloads.mariadb.com/Tools/ubuntu {{ pillar['ubuntu']['name'] }} main
{% endif %}
    - file: /etc/apt/sources.list.d/mariadb_tools.list
    - key_url: https://supplychain.mariadb.com/MariaDB-Enterprise-GPG-KEY
    - aptkey: False

update_packages_mariadb:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: mariadb_repo
      - pkgrepo: mariadb_tools_repo
    - dist_upgrade: True
