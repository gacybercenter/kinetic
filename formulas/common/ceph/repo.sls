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

ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph {{ pillar['ceph']['version'] }}
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if grains['type'] == 'arm' %}
      {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://download.ceph.com/debian-" + pillar['ceph']['version'] + "/" %}
    - name: deb [signed-by=/etc/apt/keyrings/release.asc arch=arm64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
      {% endif %}
    {% else %}
      {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://download.ceph.com/debian-" + pillar['ceph']['version'] + "/"  %}
    - name: deb [signed-by=/etc/apt/keyrings/release.asc arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
      {% endif %}
    {% endif %}
  {% endfor %}
{% else %}
  {% if grains['type'] == 'arm' %}
    - name: deb [signed-by=/etc/apt/keyrings/release.asc arch=arm64] https://download.ceph.com/debian-{{ pillar['ceph']['version'] }} {{ pillar['ubuntu']['name'] }} main
  {% else %}
    - name: deb [signed-by=/etc/apt/keyrings/release.asc arch=amd64] https://download.ceph.com/debian-{{ pillar['ceph']['version'] }} {{ pillar['ubuntu']['name'] }} main
  {% endif %}
{% endif %}
    - file: /etc/apt/sources.list.d/ceph.list
    - key_url: https://download.ceph.com/keys/release.asc
    - aptkey: False

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: ceph_repo
    - dist_upgrade: True