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
  {% for repo in pillar['cache']['nexusproxy']['repositories'] %}
    {% if grains['type'] == 'arm' %}
      {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://packages.broadcom.com/artifactory/saltproject-deb/dists/stable/main/binary-arm64/" %}
    - name: deb [signed-by=/etc/apt/keyrings/SALT-PROJECT-GPG-PUBKEY-2023.gpg arch=arm64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} stable main
      {% endif %}
    {% else %}
      {% if pillar['cache']['nexusproxy']['repositories'][repo]['url'] == "https://packages.broadcom.com/artifactory/saltproject-deb/dists/stable/main/binary-amd64/" %}
    - name: deb [signed-by=/etc/apt/keyrings/SALT-PROJECT-GPG-PUBKEY-2023.gpg arch=amd64] http://cache.{{ pillar['haproxy']['sub_zone_name'] }}:{{ pillar['cache']['nexusproxy']['port'] }}/repository/{{ repo }} stable main
      {% endif %}
    {% endif %}
  {% endfor %}
{% else %}
  {% if grains['type'] == 'arm' %}
    - name: deb [signed-by=/etc/apt/keyrings/salt-archive-keyring-2023.pgp arch=arm64] https://packages.broadcom.com/artifactory/saltproject-deb/dists/stable/main/binary-arm64/ stable main
  {% else %}
    - name: deb [signed-by=/etc/apt/keyrings/salt-archive-keyring-2023.pgp arch=amd64] https://packages.broadcom.com/artifactory/saltproject-deb/dists/stable/main/binary-amd64/ satable main
  {% endif %}
{% endif %}
    - file: /etc/apt/sources.list.d/salt.list
    - key_url: https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public
    - aptkey: False

salt_pin_version:
  file.managed:
    - name: /etc/apt/preferences.d/salt-pin-1001
    - content: |
        Pin: version {{ pillar['salt']['version'] }}
        Pin-Priority: 1001

update_packages_salt:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: salt_repo
    - dist_upgrade: True