{% set hostname = data['path'].split('/') %}

testing reactor:
  local.mine.send:
    - tgt: 'pxe'
    - arg:
      - pending_host_foo
      - mine_function: file.read
      - /var/www/html/pending_hosts/cache-5ec45ab3-25f9-494a-bd1c-d07978c83fbd
