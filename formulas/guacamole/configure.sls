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

guacamole_start:
  cmd.run:
    - name: "salt-call --local dockercompose.start /opt/guacamole/docker-compose.yml"

{% if grains['spawning'] == 0 %}

{% if grains['build_phase'] != "configure" %}

# Need to build a guacamole state for calls directly from here, as other work arounds to function as intended
# this can currently be manually executed by creating a simple main.py under modules and the executing the below under _modules
# 
# from guacamole import Session
# session = Session("https://guac.gacyberrange.org/guacamole", "mysql", "guacadmin", "guacadmin")
# session.update_user_password("guacadmin","guacadmin","NEWPASSWORDHERE"))
# session.delete_token()
#
# mod_default_user:
#   cmd.run:
#     - name: salt-call 'guac.update_user_password("https://{{ pillar['haproxy']['guacamole_domain'] }}/guacamole", "guacadmin", "guacadmin", "guacadmin", "guacadmin", "{{ pillar['guacamole']['guacadmin_password'] }}")'
#     - rquires:
#       - cmd: guacamole_guacamole_start_check

{% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}
