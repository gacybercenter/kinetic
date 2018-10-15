{% set type = pillar['type'] %}
{% set identifier = pillar['identifier'] %}

prepare_vm_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: controller*
    - sls:
      - orch/states/virtual_prep
    - pillar:
        identifier: {{ identifier }}
        type: {{ type }}

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

apply_base_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: '{{ type }}-{{ identifier }}'
    - sls:
      - formulas/common/base
    - require:
      - wait_for_minion_first_start_{{ type }}-{{ identifier }}

apply_networking_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: '{{ type }}-{{ identifier }}'
    - sls:
      - formulas/common/networking
    - require:
      - apply_base_{{ type }}-{{ identifier }}

reboot_{{ type }}-{{ identifier }}:
  salt.function:
    - tgt: '{{ type }}-{{ identifier }}'
    - name: system.reboot
    - require:
      - apply_networking_{{ type }}-{{ identifier }}

wait_for_reboot_{{ type }}-{{ identifier }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ type }}-{{ identifier }}
    - require:
      - reboot_{{ type }}-{{ identifier }}
    - timeout: 300

minion_setup_{{ type }}-{{ identifier }}:
  salt.state:
    - tgt: '{{ type }}-{{ identifier }}'
    - highstate: true
    - require:
      - wait_for_reboot_{{ type }}-{{ identifier }}
