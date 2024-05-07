## Copyright 2019 Augusta University
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

{% set type = pillar['type'] %}

{% do salt.log.info("****** Zeroing hosts [ "+type+" ] ******") %}

{% if salt.saltutil.runner('manage.up',tgt=type+'-*') %}
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
  {% if pillar['hosts'][type]['style'] == 'physical' %}
    
init_{{ type }}_poweroff:
  salt.function:
    - name: system.poweroff
    - tgt: '{{ type }}-*'
    - require:
      - salt: release_{{ type }}_ip

  {% else %}

wipe_{{ type }}_domains:
  salt.state:
    - tgt: 'role:controller'
    - tgt_type: grain
    - sls:
      - orch/states/virtual_zero
    - pillar:
        type: {{ type }}
    - concurrent: True
  {% endif %}

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