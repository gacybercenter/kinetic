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

wait_for_cache_hostname_assignment:
  salt.wait_for_event:
    - name: salt/job/*/ret/pxe
    - event_id: fun
    - id_list:
      - mine.send
    - timeout: 300
    - require:
      - rotate_cache

wait_for_mine_update:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - arg:
      - 10

{% set cache_id = salt.saltutil.runner('mine.get',
    tgt='*',
    fun='file.read')%}

echo host:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ cache_id['pxe'] }}

wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ cache_id['pxe'] }}
    - timeout: 1200

echo host2:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ cache_id['pxe'] }}

accept_cache:
  salt.wheel:
    - name: key-accept
    - match: {{ cache_id['pxe'] }}
    - require:
      - wait_for_cache_provisioning

cache_setup:
  salt.state:
    - tgt: 'cache*'
    - highstate: true
    - require:
      - accept_cache
