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

#rotate_cache:
#  salt.state:
#    - tgt: 'salt'
#    - sls:
#      - formulas/salt/rotate_cache
#    - require:
#      - pxe_setup

#wait_for_cache_hostname_assignment:
#  salt.wait_for_event:
#    - name: salt/job/*/ret/pxe
#    - event_id: fun
#    - id_list:
#      - mine.send
#    - timeout: 300
#    - require:
#      - rotate_cache

provision:
  salt.runner:
    - name: state.orchestrate
    - mods: orch/provision
