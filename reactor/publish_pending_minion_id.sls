{% set hostname = data['path'].split('/') %}

testing reactor:
  local.mine.send:
    - tgt: 'pxe'
    - arg:
      - get_pending_host_{{ hostname[5] }}
      - mine_function: file.read
      - /var/www/html/pending_hosts/{{ hostname[5] }}
