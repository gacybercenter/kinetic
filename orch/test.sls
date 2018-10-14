{% set cache_id = salt.saltutil.runner('mine.get',
    tgt='pxe',
    fun='file.read')%}

echo host:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ cache_id['pxe'] }}
