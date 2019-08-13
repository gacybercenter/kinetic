{% set type = pillar['type'] %}
{% set identifier = salt.cmd.shell("uuidgen") %}

prepare_vm_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: {{ pillar['target'] }}
    - sls:
      - orch/states/virtual_prep
    - pillar:
        identifier: {{ identifier }}
        type: {{ type }}
    - concurrent: true

wait_for_provisioning_{{ type }}-{{ identifier }}:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ type }}-{{ identifier }}
    - timeout: 300

accept_minion_{{ type }}-{{ identifier }}:
  salt.wheel:
    - name: key.accept
    - match: {{ type }}-{{ identifier }}
    - require:
      - wait_for_provisioning_{{ type }}-{{ identifier }}

wait_for_minion_first_start_{{ type }}-{{ identifier }}:
  salt.wait_for_event:
    - name: salt/minion/{{ type }}-{{ identifier }}/start
    - id_list:
      - {{ type }}-{{ identifier }}
    - timeout: 300
    - require:
      - accept_minion_{{ type }}-{{ identifier }}

run_once_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: '{{ type }}-{{ identifier }}'
    - sls:
      - formulas/common/runonce
    - require:
      - wait_for_minion_first_start_{{ type }}-{{ identifier }}

run_once_reboot_{{ type }}-{{ identifier }}:
  salt.function:
    - tgt: '{{ type }}-{{ identifier }}'
    - name: system.reboot
    - kwarg:
        at_time: 1
    - require:
      - run_once_{{ type }}-{{ identifier }}

wait_for_run_once_reboot_{{ type }}-{{ identifier }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ type }}-{{ identifier }}
    - require:
      - run_once_reboot_{{ type }}-{{ identifier }}
    - timeout: 300

set_spawning_{{ type }}-{{ identifier }}:
  salt.function:
    - name: grains.set
    - tgt: '{{ type }}-{{ identifier }}'
    - arg:
      - spawning
    - kwarg:
          val: {{ pillar['spawning'] }}
    - require:
      - wait_for_run_once_reboot_{{ type }}-{{ identifier }}

apply_base_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: '{{ type }}-{{ identifier }}'
    - sls:
      - formulas/common/base
    - require:
      - set_spawning_{{ type }}-{{ identifier }}

apply_networking_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: '{{ type }}-{{ identifier }}'
    - sls:
      - formulas/common/networking
    - require:
      - apply_base_{{ type }}-{{ identifier }}

apply_networking_reboot_{{ type }}-{{ identifier }}:
  salt.function:
    - tgt: '{{ type }}-{{ identifier }}'
    - name: system.reboot
    - kwarg:
        at_time: 1
    - require:
      - apply_networking_{{ type }}-{{ identifier }}

wait_for_apply_networking_reboot_{{ type }}-{{ identifier }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ type }}-{{ identifier }}
    - require:
      - apply_networking_reboot_{{ type }}-{{ identifier }}
    - timeout: 300

mine_update_{{ type }}-{{ identifier }}:
  salt.runner:
    - name: mine.update
    - tgt: '{{ type }}*'
    - require:
      - wait_for_apply_networking_reboot_{{ type }}-{{ identifier }}

{% if pillar['spawning']|int != 0 %}

wait_for_spawning_0_{{ type }}-{{ identifier }}:
  salt.wait_for_event:
    - name: {{ type }}/spawnzero/complete
    - id_list:
      - {{ type }}/spawnzero/complete
    - event_id: tag
    - timeout: 600
    - require:
      - mine_update_{{ type }}-{{ identifier }}

{% endif %}

minion_setup_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: '{{ type }}-{{ identifier }}'
    - highstate: true
    - failhard: true
    - require:
      - mine_update_{{ type }}-{{ identifier }}
