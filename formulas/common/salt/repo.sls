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

salt_repo:
  pkgrepo.managed:
    - humanname: SaltStack Repository
{% if (grains['type'] not in ['cache','salt','pxe'] and salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length != 0) %}
  {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last () if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
    {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
      {% if grains['type'] == 'arm' %}
        {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://repo.saltproject.io/salt/py3/ubuntu/22.04/arm64/3006/" %}
    - name: deb [signed-by=/etc/apt/keyrings/SALT-PROJECT-GPG-PUBKEY-2023.gpg arch=arm64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
        {% endif %}
      {% else %}
        {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://repo.saltproject.io/salt/py3/ubuntu/22.04/amd64/3006/" %}
    - name: deb [signed-by=/etc/apt/keyrings/SALT-PROJECT-GPG-PUBKEY-2023.gpg arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} {{ pillar['ubuntu']['name'] }} main
        {% endif %}
      {% endif %}
    {% endfor %}
  {% endfor %}
{% else %}
  {% if grains['type'] == 'arm' %}
    - name: deb [signed-by=/etc/apt/keyrings/SALT-PROJECT-GPG-PUBKEY-2023.gpg arch=arm64] https://repo.saltproject.io/salt/py3/ubuntu/{{ pillar['ubuntu']['version'] }}/arm64/{{ pillar['salt']['version'] }}/ {{ pillar['ubuntu']['name'] }} main
  {% else %}
    - name: deb [signed-by=/etc/apt/keyrings/SALT-PROJECT-GPG-PUBKEY-2023.gpg arch=amd64] https://repo.saltproject.io/salt/py3/ubuntu/{{ pillar['ubuntu']['version'] }}/amd64/{{ pillar['salt']['version'] }}/ {{ pillar['ubuntu']['name'] }} main
  {% endif %}
{% endif %}
    - file: /etc/apt/sources.list.d/salt.list
    - key_url: https://repo.saltproject.io/salt/py3/ubuntu/22.04/arm64/3006/SALT-PROJECT-GPG-PUBKEY-2023.gpg
    - aptkey: False

update_packages_salt:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: salt_repo
    - dist_upgrade: True