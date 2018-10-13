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

wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ contains 'cache' }}
    - timeout: 10

validate_cache_key:
  salt.wheel:
    - name: key.accept
    - match: cache*
