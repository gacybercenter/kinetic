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

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

guacamole_mysql:
  cmd.run:
    - name: docker-compose up -d mysql
    - cwd: /opt/guacamole
    - unless:
      - docker ps | grep mysql

guacamole_mysql_check:
  cmd.run:
    - name: docker logs mysql | grep -q guacamole_db
    - retry:
      - attempts: 5
      - interval: 20
      - until: True

guacamole_guacd:
  cmd.run:
    - name: docker-compose up -d guacd
    - cwd: /opt/guacamole
    - rquires:
      - cmd: guacamole_mysql_check
    - unless:
      - docker ps | grep guacd

guacamole_guacd_check:
  cmd.run:
    - name: docker logs guacd | grep -q 4822
    - retry:
      - attempts: 5
      - interval: 20
      - until: True

guacamole_guacamole:
  cmd.run:
    - name: docker-compose up -d guacamole
    - cwd: /opt/guacamole
    - rquires:
      - cmd: guacamole_guacd_check
    - unless:
      - docker ps | grep guacamole