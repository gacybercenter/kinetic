{% set host = salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] %}

wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ host }}
    - timeout: 10
