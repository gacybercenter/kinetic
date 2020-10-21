## This routine is called on a fresh minion whose key was just accepted.

{% import 'formulas/common/macros/orchestration.sls' as orchestration with context %}

{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set targets = pillar['targets'] %}

{% if pillar['hosts'][type]['style'] == 'physical' %}
  {% set role = pillar['hosts'][type]['role'] %}
{% else %}
  {% set role = type %}
{% endif %}

apply_base_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/common/base
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0

### This macro renders to a block if there are unmet dependencies
{{ orchestration.needs_check_one(type=type, phase='networking')}}

apply_networking_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/common/networking
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - apply_base_{{ type }}

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.reboot_and_wait(type=type, targets=targets, phase='networking')}}

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.build_phase_update(type=type, targets=targets, phase='networking')}}

### This macro renders to a block if there are unmet dependencies
{{ orchestration.needs_check_one(type=type, phase='install')}}

apply_install_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/{{ role }}/install
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - wait_for_{{ type }}_networking_reboot

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.build_phase_update(type=type, targets=targets, phase='install')}}

### This macro renders to a block if there are unmet dependencies
{{ orchestration.needs_check_one(type=type, phase='configure')}}

apply_configure_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - highstate: True
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - apply_install_{{ type }}

## this macro executes a reboot and wait loop
{{ orchestration.reboot_and_wait(type=type, targets=targets, phase='configure')}}

## This macro updates the build_phase grain and forces a mine update
{{ orchestration.build_phase_update(type=type, targets=targets, phase='configure')}}
