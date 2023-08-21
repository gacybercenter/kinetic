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
  - /formulas/common/fluentd/fluentd

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

guacamole_recording_setup:
  file.directory:
    - name: /opt/guacamole/recordings
    - makedirs: True
    - user: 1000
    - group: 1001
    - dir_mode: 2750
    - file_mode: 750
    - recurse:
      - user
      - group
      - mode

guacamole_pull:
  cmd.run:
    - name: "salt-call --local dockercompose.pull /opt/guacamole/docker-compose.yml"
    - unless:
      - docker image ls | grep -q 'guacamole/guacd'
      - docker image ls | grep -q 'guacamole/guacamole'
    - require:
      - file: guacamole_recording_setup

guacamole_up:
  cmd.run:
    - name: "salt-call --local dockercompose.up /opt/guacamole/docker-compose.yml"
    - require:
      - guacamole_pull
    - unless:
      - docker exec guacamole whoami | grep -q guacamole

ROOT_path:
  cmd.run:
    - name: "docker exec guacamole mv /home/guacamole/tomcat/webapps/guacamole.war /home/guacamole/tomcat/webapps/ROOT.war"
    - require:
      - guacamole_up
    - unless:
      - docker exec guacamole ls -al /home/guacamole/tomcat/webapps/ | grep -q ROOT.war

{% if grains['spawning'] == 0 %}

{% if grains['build_phase'] != "configure" %}


{% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}
