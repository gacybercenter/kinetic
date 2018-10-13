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

{% set cache_id = salt.saltutil.runner('mine.get',
    tgt='pxe',
    fun='pending_hosts').split('\n') %}

echo {{ cache_id['pxe'][0] }}:
  salt.function:
    - name: cmd.run
    - tgt: salt

#rotate_cache:
#  salt.state:
#    - tgt: 'salt'
#    - sls:
#      - formulas/salt/rotate_cache    
#    - require:
#      - pxe_setup


wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ salt['mine.get']('pxe', 'pending_hosts') }}
    - timeout: 600

##cache_setup:
##  salt.state:
##    - tgt: 'cache*'
##    - highstate: true
##    - require:
##      - provision_cache
