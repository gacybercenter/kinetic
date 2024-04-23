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


## if running a full environment init, you should wipe all keys to ensure that the
## mine is empty so phase checks don't pass on old data
## They below will wipe everything that has a '-' in the minion_id, e.g.
## everything except salt and pxe

{% for type in pillar['hosts'] if salt['pillar.get']('hosts:'+type+':enabled', 'True') == True %}
  {% do salt.log.info("****** Service is set to Enabled for: " + type) %}
  {% if salt.saltutil.runner('manage.up',tgt=type+'*') %}
  {% do salt.log.info("****** Triggering DHCP IP Address Release for: " + type) %}
release_{{ type }}_ip:
  salt.function:
    - name: cmd.run
    - tgt: '{{ type }}-*'
    - arg:
      - 'dhclient -r'
    - onlyif:
      - salt-key -l acc | grep -q "{{ type }}"

  {% do salt.log.info("****** Powering Off systems for Service: " + type) %}
init_{{ type }}_poweroff:
  salt.function:
    - name: system.poweroff
    - tgt: '{{ type }}-*'
    - require:
      - salt: release_{{ type }}_ip

## This gives hosts that were given a shutdown order the ability to shut down
## There have been cases where a zeroize reset command was issued before a
## successful shutdown
init_{{ type }}_sleep:
  salt.function:
    - name: test.sleep
    - tgt: '{{ pillar['salt']['name'] }}'
    - kwarg:
        length: 10


  {% do salt.log.info("****** Deleting Salt Keys for: " + type) %}
wipe_{{ type }}_keys:
  salt.wheel:
    - name: key.delete
    - match: '{{ type }}-*'
  {% endif %}
{% endfor %}

## Start a runner for every endpoint type.  Whether or not this runner actually does anything is determined
## in the waiting room
{% for type in pillar['hosts'] if salt['pillar.get']('hosts:'+type+':enabled', 'True') == True %}
  {% if pillar['hosts'][type]['style'] == 'physical' %}
    {% set role = pillar['hosts'][type]['role'] %}
  {% else %}
    {% set role = type %}
  {% endif %}

{{ type }}_exec_runner_delay:
  salt.function:
    - name: test.sleep
    - tgt: '{{ pillar['salt']['name'] }}'
    - kwarg:
        length: 60
    - parallel: true

  {% do salt.log.info("****** Creating Execution Runner for: " + type) %}
create_{{ type }}_exec_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/waiting_room
        pillar:
          type: {{ type }}
          needs: {{ salt['pillar.get']('hosts:'+role+':needs', {}) }}
    - parallel: true
    - require:
      - salt: {{ type }}_exec_runner_delay

{{ type }}_create_exec_runner_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 2
{% endfor %}