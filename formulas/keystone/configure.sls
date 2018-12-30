include:
  - /formulas/keystone/install
  - formulas/common/base
  - formulas/common/networking

/etc/keystone/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/keystone.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') }}
        sql_connection_string: 'connection = mysql+pymysql://keystone:{{ pillar['keystone']['keystone_mysql_password'] }}@{{ address }}/keystone'
{% endfor %}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') }}
        memcache_servers: memcache_servers = {{ address }}:11211
{% endfor %}
    - order: 1
