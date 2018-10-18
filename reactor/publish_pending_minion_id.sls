{% set hostname = data['path'].split('/') %}

publish pending id:
  local.mine.send:
    - tgt: 'pxe'
    - arg:
      - minionmanage.populate
      - {{ data['path'] }}
