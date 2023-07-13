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

### This macro is used to construct needs-check routines
### for use in the orchestrator
### This loop will block until confirmation is received that all networking
### deps have been met.  The logic is very similar to the initial dep check loop
### adding an additional one here will ensure that the deps needed for the
### next phase of the orch have been met, rather than just the bits needed to
### start

{%- macro needs_check_one(type, phase) -%}

{% if salt['pillar.get']('hosts:'+type+':needs:'+phase, {}) != {} %}
{{ type }}_{{ phase }}_phase_check_loop::
  salt.runner:
    - name: needs.check_one
    - kwarg:
        needs: {{ salt['pillar.get']('hosts:'+type+':needs:'+phase, {}) }}
        type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - apply_{{ phase }}_{{ type }}
{% endif %}

{%- endmacro -%}

## This macro updates the phase grain and pushes it to the
## mine
{%- macro build_phase_update(type, targets, phase) -%}

set_build_phase_{{ phase }}_{{ type }}:
  salt.function:
    - name: grains.setval
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - arg:
      - build_phase
      - {{ phase }}
    - require:
      - apply_{{ phase }}_{{ type }}

set_build_phase_{{ phase }}_mine_{{ type }}:
  salt.function:
    - name: mine.update
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - require:
      - set_build_phase_{{ phase }}_{{ type }}

{%- endmacro -%}

## This macro executes a reboot-and-wait routine
{%- macro reboot_and_wait(type, targets, phase) -%}

{% if type in ['controller', 'controllerv2', 'compute', 'computev2', 'storage', 'storagev2', 'container', 'containerv2'] and phase == 'networking' %}
wait_for_{{ type }}_{{ phase }}_reboot_physical:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
  {% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
  {% endfor %}
    - timeout: 600
{% else %}

reboot_{{ type }}_{{ phase }}:
  salt.function:
    - tgt:
  {% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
  {% endfor %}
    - tgt_type: list
    - name: system.reboot
    - require:
      - apply_{{ phase }}_{{ type }}

wait_for_{{ type }}_{{ phase }}_reboot:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
  {% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
  {% endfor %}
    - require:
      - reboot_{{ type }}_{{ phase }}
    - timeout: 600
{% endif %}

{%- endmacro -%}

{%- endmacro -%}
