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
      - 'cache*'
    - timeout: 10

echo foo:
  salt.function:
    - name: cmd.run
    - require:
      - salt: wait_for_cache_provisioning
