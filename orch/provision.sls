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

minion_setup:
  salt.state:
    - tgt: '{{ host }}'
    - highstate: true
    - require:
      - wait_for_minion_first_start
