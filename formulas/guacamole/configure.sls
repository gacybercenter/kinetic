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
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

guacamole_guacd_start:
  cmd.run:
    - name: docker-compose up -d guacd
    - cwd: /opt/guacamole
    - unless:
      - docker ps | grep -q guacd

guacamole_guacamole_pull:
  cmd.run:
    - name: docker-compose up -d guacamole
    - cwd: /opt/guacamole
    - rquires:
      - cmd: guacamole_mysql_check
    - unless:
      -  docker image ls | grep -q 'guacamole/guacamole'

guacamole_guacamole_pull_check:
  cmd.run:
    - name: docker image ls | grep -q 'guacamole/guacamole'
    - retry:
      - attempts: 10
      - interval: 20
      - until: True
    - rquires:
      - cmd: guacamole_guacamole_pull

guacamole_guacamole_start:
  cmd.run:
    - name: docker-compose up -d guacamole
    - cwd: /opt/guacamole
    - rquires:
      - cmd: guacamole_guacamole_pull_check
    - unless:
      - docker ps | grep -q guacamole

guacamole_guacamole_start_check:
  cmd.run:
    - name: docker logs guacamole | grep -q 'Georgia Cyber Range'
    - retry:
      - attempts: 10
      - interval: 20
      - until: True
    - rquires:
      - cmd: guacamole_guacamole_start

{% if grains['spawning'] == 0 %}

{% if grains['build_phase'] != "configure" %}
mod_default_user:
  salt.function:
    - name: guac.update_password
    - tgt: guacamole
    - arg:
      - host: https://{{ pillar['haproxy']['guacamole_domain'] }}/guacamole
      - authuser: guacadmin
      - authpass: guacadmin
      - username: guacadmin
      - oldpassword: guacadmin
      - newpassword: {{ pillar['guacamole']['guacadmin_password'] }}

  {% for group in ['range', 'public'] %}
create_group_{{ group }}:
  salt.function:
    - name: guac.create_group
    - tgt: guacamole
    - arg:
      - host: https://{{ pillar['haproxy']['guacamole_domain'] }}/guacamole
      - authuser: guacadmin
      - authpass: {{ pillar['guacamole']['guacadmin_password'] }}
      - identifier: {{ group }}

    {% if group == 'range' %}
set_{{ group }}_permissions:
  salt.function:
    - name: guac.update_permissions
    - tgt: guacamole
    - arg:
      - host: https://{{ pillar['haproxy']['guacamole_domain'] }}/guacamole
      - authuser: guacadmin
      - authpass: {{ pillar['guacamole']['guacadmin_password'] }}
      - identifier: {{ group }}
      - operation: add
      - cuser: True
      - cusergroup: True
      - cconnect: True
      - cconnectgroup: True
      - cshare: True
      - admin: True
    {% endif %}
  {% endfor %}
{% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}
