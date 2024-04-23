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

## This is the maximum amount of time an endpoint should wait for the start
## signal. It will need to be at least two hours (generally).  Less is
## fine for testing

{% do salt.log.info("****** Executing Needs Check for: " + type) %}
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

{% do salt.log.info("****** Creating Orchestration Runner for: " + type) %}
orch_{{ type }}_init_exec_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/generate
        pillar:
          type: {{ type }}
    - require:
      - {{ type }}_phase_check_init
