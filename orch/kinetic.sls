include:
  - orch/prep

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
      - {{ salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] }}
    - timeout: 1200
    - require:
      - sls: orch/prep

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
