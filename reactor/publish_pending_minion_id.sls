{% set hostname = data['path'].split('/') %}

testing reactor:
  local.mine.send:
    - tgt: 'pxe'
    - arg:
      - file.read
      - /var/www/html/pending_hosts/{{ hostname[5] }}
