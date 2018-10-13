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

provision_cache:
  salt.state:
    - tgt: 'salt'
    - sls:
      - formulas/salt/provision_cache
    - require:
      - rotate_cache

cache_setup:
  salt.state:
    - tgt: 'cache*'
    - highstate: true
    - require:
      - provision_cache
