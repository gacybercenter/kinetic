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

mod_default_user:
  guac.update_user_password:
    - username: guacadmin
    - oldpassword: guacadmin
    - newpassword: {{ pillar['guacamole']['guacadmin_password'] }}


# {{ guacamole_domain }}/guacamole


{% for group in ['range', 'public'] %}
create_group_{{ group }}:
  guac.create_user_group:
    - identifier: {{ group }}

  {% if {{ group }} == "range" %}
set_{{ group }}_permissions:
  guac.create_user_group:
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

{{ spawn.spawnzero_complete() }}


{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}


