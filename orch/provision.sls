{% set host = salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] %}

wait_for_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ host }}
    - timeout: 1200

accept_minion:
  salt.wheel:
    - name: key.accept
    - match: {{ host }}
    - require:
      - wait_for_provisioning

wait_for_minion_first_start:
  salt.wait_for_event:
    - name: salt/minion/{{ host }}/start
    - id_list:
      - {{ host }}
    - timeout: 60
    - require:
      - accept_minion

apply_base:
  salt.state:
    - tgt: '{{ host }}'
    - sls:
      - formulas/common/base
    - require:
      - wait_for_minion_first_start

apply_networking:
  salt.state:
    - tgt: '{{ host }}'
    - sls:
      - formulas/common/networking
    - require:
      - apply_base

reboot_{{ host }}:
  salt.function:
    - tgt: '{{ host }}'
    - name: system.reboot
    - require:
      - apply_networking

wait_for_reboot:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ host }}
    - require:
      - reboot_{{ host }}
    - timeout: 300

minion_setup:
  salt.state:
    - tgt: '{{ host }}'
    - highstate: true
    - require:
      - wait_for_reboot
