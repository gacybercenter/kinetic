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
