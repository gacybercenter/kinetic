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

{{ pillar['openstack']['version'] }}_repo:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - {{ pillar['openstack']['version'] }}
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last () if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
    {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
      {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "http://ubuntu-cloud.archive.canonical.com/ubuntu" %}
    - name: deb [signed-by=/etc/apt/keyrings/Release.gpg arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }}-updates/{{ pillar['openstack']['version'] }} main
      {% endif %}
    {% endfor %}
  {% endfor %}
{% else %}
    - name: deb [signed-by=/etc/apt/keyrings/Release.gpg arch=amd64] http://ubuntu-cloud.archive.canonical.com/ubuntu {{ pillar['ubuntu']['name'] }}-updates/{{ pillar['openstack']['version'] }} main
{% endif %}
    - file: /etc/apt/sources.list.d/{{ pillar['openstack']['version'] }}.list
    - key_url: http://ubuntu-cloud.archive.canonical.com/ubuntu/dists/{{ pillar['ubuntu']['name'] }}-updates/{{ pillar['openstack']['version'] }}/Release.gpg
    - aptkey: False

update_packages_{{ pillar['openstack']['version'] }}:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: {{ pillar['openstack']['version'] }}_repo
    - dist_upgrade: True

