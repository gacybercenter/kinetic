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

fluentd_repo:
  pkgrepo.managed:
    - humanname: Treasure Data
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://packages.treasuredata.com/4/ubuntu/" + pillar['ubuntu']['name'] + "/" %}
    - name: deb [signed-by=/etc/apt/keyrings/GPG-KEY-td-agent arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} contrib
    {% endif %}
  {% endfor %}
{% else %}
    - name: deb [signed-by=/etc/apt/keyrings/GPG-KEY-td-agent arch=amd64] https://packages.treasuredata.com/4/ubuntu/{{ pillar['ubuntu']['name'] }} {{ pillar['ubuntu']['name'] }} contrib
{% endif %}
    - file: /etc/apt/sources.list.d/fluentd.list
    - key_url: https://packages.treasuredata.com/GPG-KEY-td-agent
    - aptkey: False

update_packages_fluentd:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: fluentd_repo
    - dist_upgrade: True