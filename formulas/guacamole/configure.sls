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

/opt/guacamole/docker-compose.yml:
  file.managed:
    - source: salt://formulas/guacamole/files/docker-compose.yml
    - makedirs: True
    - template: jinja
    - defaults: 
        guac_password: {{ pillar['guacamole']['guac_password'] }}
        mysql_password: {{ pillar['guacamole']['mysql_password'] }}s

/opt/guacamole/init/initdb.sql:
  file.managed:
    - source: salt://formulas/guacamole/files/initdb.sql
    - makedirs: True

/opt/guacamole/guacamole/extensions:
  file.directory:
    - makedirs: True

guacamole_quickconnect:
  archive.extracted:
    - names: /opt/guacamole/guacamole/extensions
    - source: https://downloads.apache.org/guacamole/1.3.0/binary/guacamole-auth-quickconnect-1.3.0.tar.gz
    - source_hash: https://www.apache.org/dist/guacamole/1.3.0/binary/guacamole-auth-quickconnect-1.3.0.tar.gz.sha256
    - require:
      - file: /opt/guacamole/guacamole/extensions

guacamole_branding:
  file.managed:
    - names: /opt/guacamole/guacamole/extensions
    - source: salt://formulas/guacamole/files/branding.jar # source: https://github.com/Zer0CoolX/guacamole-customize-loginscreen-extension
    - require:
      - file: /opt/guacamole/guacamole/extensions

guacamole_start:
  cmd.run:
    - name: docker-compose up -d
    - cwd: /opt/guacamole
    - require:
      - file: /opt/guacamole/docker-compose.yml
      - file: /opt/guacamole/init/initdb.sql
      - file: /opt/guacamole/guacamole/extensions
      - archive: guacamole_quickconnect
    - unless:
      - docker-compose ps | grep -q guacd