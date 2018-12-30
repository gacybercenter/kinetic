include:
  - /formulas/keystone/install
  - formulas/common/base
  - formulas/common/networking

/etc/keystone/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/keystone.conf
    - template: jinja
    - defaults:
        token_provider: provider = fernet
        sql_connection_string: 'connection = mysql+pymysql://keystone:{{ pillar['keystone_password'] }}@{{ pillar ['mysql_configuration']['address'] }}/keystone'
        memcache_servers: memcache_servers = {{ pillar['memcached_servers']['address'] }}:11211
    - order: 1
