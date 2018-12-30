include:
  - /formulas/keystone/install
  - formulas/common/base
  - formulas/common/networking

/etc/keystone/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/keystone.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://keystone:{{ pillar['keystone']['keystone_mysql_password'] }}@{{ salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain')[0] }}/keystone'
        memcache_servers: memcache_servers = {{ salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') }}:11211
    - order: 1
