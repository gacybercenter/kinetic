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
      - cache-fcbc711f-40f9-4c5c-8ace-43c8080cb566
    - timeout: 10

auth flag:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - echo foo
    - require:
      - salt: wait_for_cache_provisioning
