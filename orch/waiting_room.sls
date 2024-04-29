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

{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}
{% set targets = pillar['targets'] %}
{% set style = pillar['hosts'][type]['style'] %}

{% if salt['pillar.get']('universal', False) == False %}
master_setup:
  salt.state:
    - tgt: '{{ pillar['salt']['name'] }}'
    - highstate: true
    - fail_minions:
      - '{{ pillar['salt']['name'] }}'
    - queue: true

pxe_setup:
  salt.state:
    - tgt: '{{ pillar['pxe']['name'] }}'
    - highstate: true
    - fail_minions:
      - '{{ pillar['pxe']['name'] }}'
    - queue: true
{% endif %}

{{ type }}_phase_check_init:
  salt.runner:
    - name: needs.check_all
    - kwarg:
        needs: {{ needs }}
        type: {{ type }}
    - retry:
        interval: 60
        attempts: 240
        splay: 60

deploy_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/deploy
        pillar:
          type: {{ type }}
          targets: {{ targets }}
    - require:
      - {{ type }}_phase_check_init

provision_{{ type }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/provision
        pillar:
          type: {{ type }}
          targets: {{ targets }}
    - require:
      - {{ type }}_phase_check_init
      - deploy_{{ type }}