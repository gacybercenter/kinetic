{% set hostname = data['path'].split('/') %}

testing reactor:
  local.mine.send:
    - tgt: 'pxe'
    - arg:
      - pending_host_foobar
      - mine_function: file.read
      - /var/www/html/pending_hosts/{{ hostname[5] }}
