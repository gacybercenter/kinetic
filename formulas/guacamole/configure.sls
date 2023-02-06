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

guacamole_pull:
  cmd.run:
    - name: "salt-call --local dockercompose.pull /opt/guacamole/docker-compose.yml"
    - unless:
      - docker image ls | grep -q 'guacamole/guacd'
      - docker image ls | grep -q 'guacamole/guacamole'

guacamole_up:
  cmd.run:
    - name: "salt-call --local dockercompose.up /opt/guacamole/docker-compose.yml"
    - require:
      - guacamole_pull
    - unless:
      - docker exec -it guacamole whoami | grep -q guacamole

ROOT_path:
  cmd.run:
    - name: "docker exec guacamole mv /home/guacamole/tomcat/webapps/guacamole.war /home/guacamole/tomcat/webapps/ROOT.war"
    - require:
      - guacamole_up
    - unless:
      - docker exec guacamole ls -al /home/guacamole/tomcat/webapps/ | grep -q ROOT.war

{% if grains['spawning'] == 0 %}

#update_guacadmin_password:
#  gucamole.update_user_password:
#    - host: {{ pillar['haproxy']['guacamole_domain'] }}
#    - data_source: "mysql"
#    - username: "guacadmin"
#    - password: {{ pillar['guacamole']['guacadmin_old_password'] }}
#    - guac_username: {{ user }}
#    - oldpassword: {{ pillar['guacamole']['guacadmin_old_password'] }}
#    - newpassword: {{ pillar['guacamole']['guacadmin_password'] }}

#{% for user in users %}
#create_{{ user }}_password:
#  gucamole.create_users:
#    - host: {{ pillar['haproxy']['guacamole_domain'] }}
#    - data_source: "mysql"
#    - username: "guacadmin"
#    - password: {{ pillar['guacamole']['guacadmin_password'] }}
#    - guac_username: {{ user }}
#    - newpassword: {{ pillar['guacamole']['temporary_password'] }}
#{% endfor %}

{% if grains['build_phase'] != "configure" %}


{% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}
