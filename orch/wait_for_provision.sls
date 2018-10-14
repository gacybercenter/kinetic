test:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] }}

wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] }}
    - timeout: 1200
