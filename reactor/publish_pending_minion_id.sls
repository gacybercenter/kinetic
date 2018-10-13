{% set hostname = data['path'].split('/') %}

testing reactor:
  local.mine.send:
    - tgt: 'pxe'
    - arg:
      - file.read
      - {{ data['path'] }}
