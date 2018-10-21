{% set type = data['path'].split('/')[4] %}

publish pending id:
  local.mine.send:
    - tgt: 'pxe'
    - arg:
      - minionmanage.populate
      - {{ data['path'] }}
