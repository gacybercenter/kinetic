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
  - /formulas/common/fluentd/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

guacamole_recording_setup:
  file.directory:
    - name: /opt/guacamole/recordings
    - makedirs: True
    - user: 1000
    - group: 1001
    - dir_mode: "2750"
    - file_mode: "2750"
    - recurse:
      - user
      - group
      - mode

guacamole_internal:
  docker_network.present:
    - name: guacamole_internal
    - internal: True

guacamole_default:
  docker_network.present:
    - name: guacamole_default

# Convert to guacd binary package
guacamole_guacd:
  docker_container.running:
    - name: guacd
    - image: guacamole/guacd:1.5.5
    - restart_policy: always
    - binds:
      - /opt/guacamole/recordings:/var/lib/guacamole/recordings:rw
    - ports:
      - 4822
    - port_bindings:
      - 4822:4822
    - networks:
      - guacamole_default
      - guacamole_internal
    - require:
      - file: guacamole_recording_setup
      - docker_network: guacamole_internal
      - docker_network: guacamole_default

guacamole_guacamole:
  docker_container.running:
    - name: guacamole
    - image: guacamole/guacamole:1.5.5
    - restart_policy: always
    - binds:
      - /opt/guacamole/guacamole:/data
      - /opt/guacamole/recordings:/var/lib/guacamole/recordings:rw
    - ports:
      - 8080
    - port_bindings:
      - 8080:8080
    - environment:
      - GUACD_HOSTNAME: guacd
      - GUACD_PORT: 4822
      - MYSQL_HOSTNAME: {{ pillar['haproxy']['guacamole_domain'] }}
      - MYSQL_DATABASE: {{ pillar['integrated_services']["guacamole"]['configuration']['dbs'][0] }}
      - MYSQL_USER: guacamole
      - MYSQL_PASSWORD: {{ pillar['guacamole']['guacamole_mysql_password'] }}
      - GUACAMOLE_HOME: /data
      - LOG_LEVEL: info
    - links:
      - guacd: guacd
    - networks:
      - guacamole_default
      - guacamole_internal
    - require:
      - file: guacamole_recording_setup
      - docker_network: guacamole_internal
      - docker_network: guacamole_default
      - docker_container: guacamole_guacd
{% if grains['spawning'] == 0 %}

  {% if grains['build_phase'] != "configure" %}
update_guacadmin_password:
  guacamole.update_user_password:
    - name: update_guacadmin_password
    - host: "https://{{ pillar['haproxy']['guacamole_domain'] }}/guacamole"
    - username: "guacadmin"
    - password: "guacadmin"
    - guac_new_password: {{ pillar['guacamole']['guacadmin_password'] }}
    - guac_username: "guacadmin"
    - guac_old_password: "guacadmin"
    - retry:
        attempts: 3
        interval: 30
  {% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

ROOT_path:
  cmd.run:
    - name: "docker exec guacamole mv /home/guacamole/tomcat/webapps/guacamole.war /home/guacamole/tomcat/webapps/ROOT.war"
    - require:
      - docker_container: guacamole_guacamole
    - unless:
      - docker exec guacamole ls -al /home/guacamole/tomcat/webapps/ | grep -q ROOT.war