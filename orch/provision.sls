## Copyright 2018 Augusta University
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

## This routine is called on a fresh minion whose key was just accepted.

{% import 'formulas/common/macros/orchestration.sls' as orchestration with context %}

{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set targets = pillar['targets'] %}

{% do salt.log.info("****** Running provision for [ "+type+" ] ******") %}

{% if pillar['hosts'][type]['style'] == 'physical' %}
  {% set role = pillar['hosts'][type]['role'] %}
{% else %}
  {% set role = type %}
{% endif %}

{% do salt.log.info("****** Applying Base for [ "+type+" ] ******") %}
apply_base_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/common/base
    - timeout: 1200
    - retry:
        interval: 10
        attempts: 2
        splay: 0

### This macro renders to a block if there are unmet dependencies
{{ orchestration.needs_check_one(type=type, phase='networking') }}

{% do salt.log.info("****** Applying Networking for [ "+type+" ] ******") %}
apply_networking_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/common/networking
    - timeout: 1200
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - apply_base_{{ type }}

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.reboot_and_wait(type=type, targets=targets, phase='networking') }}

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.build_phase_update(type=type, targets=targets, phase='networking') }}

### This macro renders to a block if there are unmet dependencies
{{ orchestration.needs_check_one(type=type, phase='install') }}

{% do salt.log.info("****** Applying Install for [ "+type+" ] ******") %}
apply_install_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/{{ role }}/install
    - timeout: 1200
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - wait_for_{{ type }}_networking_reboot

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.build_phase_update(type=type, targets=targets, phase='install') }}

### This macro renders to a block if there are unmet dependencies
{{ orchestration.needs_check_one(type=type, phase='configure') }}

{% do salt.log.info("****** Applying Configure for [ "+type+" ] ******") %}
apply_configure_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/{{ role }}/configure
#    - highstate: True
    - timeout: 1200
    # - retry:
    #     interval: 10
    #     attempts: 2
    #     splay: 0
    - require:
      - apply_install_{{ type }}

## this macro executes a reboot and wait loop
{{ orchestration.reboot_and_wait(type=type, targets=targets, phase='configure') }}

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.build_phase_update(type=type, targets=targets, phase='configure') }}
