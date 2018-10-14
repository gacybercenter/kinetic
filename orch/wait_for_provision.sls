{% set host = salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] %}

test:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ host }} working 

wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - cache-0a90ddc7-4b84-44ae-99f5-51017d0d7034
    - timeout: 1200
