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
{% set style = pillar['hosts'][type]['style'] %}

{% if salt['pillar.get']('universal', False) == False %}
master_setup:
  salt.state:
    - tgt: '{{ pillar['salt']['name'] }}'
    - highstate: true
    - fail_minions:
      - '{{ pillar['salt']['name'] }}'

pxe_setup:
  salt.state:
    - tgt: '{{ pillar['pxe']['name'] }}'
    - highstate: true
    - fail_minions:
      - '{{ pillar['pxe']['name'] }}'
{% endif %}

## Create the special targets dictionary and populate it with the 'id' of the target (either the physical uuid or the spawning)
## as well as its ransomized 'uuid'.
{% set targets = {} %}
{% if style == 'physical' %}
## create and endpoints dictionary of all physical uuids
  {% set endpoints = salt.saltutil.runner('mine.get',tgt=pillar['pxe']['name'],fun='redfish.gather_endpoints')[pillar['pxe']['name']] %}
  {% for id in pillar['hosts'][type]['uuids'] %}
    {% set targets = targets|set_dict_key_value(id+':api_host', endpoints[id]) %}
    {% set targets = targets|set_dict_key_value(id+':uuid', salt['random.get_str']('64', punctuation=False)|uuid) %}
  {% endfor %}
{% elif style == 'virtual' %}
  {% set controllers = salt.saltutil.runner('manage.up',tgt='role:controller',tgt_type='grain') %}
  {% set offset = range(controllers|length)|random %}
  {% for id in range(pillar['hosts'][type]['count']) %}
    {% set targets = targets|set_dict_key_value(id|string+':spawning', loop.index0) %}
    {% set targets = targets|set_dict_key_value(id|string+':controller', controllers[(loop.index0 + offset) % controllers|length]) %}
    {% set targets = targets|set_dict_key_value(id|string+':uuid', salt['random.get_str']('64', punctuation=False)|uuid) %}
  {% endfor %}
{% endif %}

# type is the type of host (compute, controller, etc.)
# provision determines whether or not zeroize will just create a blank minion,
# or fully configure it

{% do salt.log.info("Zeroing hosts: "+type) %}
zeroize_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/zeroize
        pillar:
          type: {{ type }}
          targets: {{ targets }}

{% do salt.log.info("Running provision for: "+type) %}
provision_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          targets: {{ targets }}
    - require:
      - zeroize_{{ type }}
