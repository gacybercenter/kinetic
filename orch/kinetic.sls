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

test2:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] }}

wait_for_cache_provisioning:
  salt.state:
    - tgt: salt
    - sls:
      - orch/wait_for_provision

accept_cache:
  salt.wheel:
    - name: key-accept
    - match: {{ salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] }}
    - require:
      - wait_for_cache_provisioning

cache_setup:
  salt.state:
    - tgt: 'cache*'
    - highstate: true
    - require:
      - accept_cache
