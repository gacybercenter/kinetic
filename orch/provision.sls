{% set host = salt.saltutil.runner('mine.get', tgt='pxe', fun='file.read')['pxe'] %}

wait_for_cache_provisioning:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ host }}
    - timeout: 1200

accept_cache:
  salt.wheel:
    - name: key.accept
    - match: {{ host }}
    - require:
      - wait_for_cache_provisioning
