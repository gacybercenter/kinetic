master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

pxe_setup:
  salt.state:
    - tgt: 'pxe'
    - highstate: true
    - require:
      - master_setup

{% for type in pillar['hosts'] %}
rotate_{{ type }}:
  salt.state:
    - tgt: 'salt'
    - sls:
      - orch/states/rotate
    - pillar:
      - '{"type": "{{ type }}"}'
    - require:
      - pxe_setup

delete_cache_key:
  salt.wheel:
    - name: key.delete
    - match: 'cache*'
    - require:
      - rotate_cache

wait_for_cache_hostname_assignment:
  salt.wait_for_event:
    - name: salt/job/*/ret/pxe
    - event_id: fun
    - id_list:
      - mine.send
    - timeout: 300
    - require:
      - rotate_cache

provision:
  salt.runner:
    - name: state.orchestrate
    - mods: orch/provision
