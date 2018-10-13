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

rotate_cache:
  salt.state:
    - tgt: 'salt'
    - sls:
      - formulas/salt/rotate_cache    
    - require:
      - pxe_setup

wait_for_cache_identity_assignment:
  salt.wait_for_event:
    - name: salt/beacon/pxe/log/bootstrap/request/event

wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - pend
    - event_id: act
    - timeout: 600
    - require:
      - rotate_cache

validate_cache_key:
  salt.wheel:
    - name: key.accept
    - match: cache*
    - require:
      - wait_for_cache_provisioning

cache_setup:
  salt.state:
    - tgt: 'cache*'
    - highstate: true
    - require:
      - validate_cache_key
