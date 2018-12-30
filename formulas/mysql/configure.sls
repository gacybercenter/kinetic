include:
  - /formulas/mysql/install
  - formulas/common/base
  - formulas/common/networking

/etc/mysql/mariadb.conf.d/99-openstack.cnf:
  file.managed:
    - source: salt://formulas/mysql/files/99-openstack.cnf
    - makedirs: True
    - template: jinja
    - defaults:
        ip_address: {{ grains['ipv4'][0] }}
    - order: 1

mariadb:
  service.running:
    - enable: True
    - watch:
      - file: /etc/mysql/mariadb.conf.d/99-openstack.cnf
    - order: 2

root:
  mysql_user.present:
    - host: localhost
    - password: {{ pillar ['mysql_root_password'] }}
    - connection_unix_socket: /var/run/mysqld/mysqld.sock

{% for service in pillar['openstack_services'] %}

create_{{ service }}_db:
  mysql_database.present:
    - name: {{ service }}
    - connection_unix_socket: /var/run/mysqld/mysqld.sock

  {% for address in salt['mine.get']('type:'+service, 'network.ip_addrs', tgt_type='grain') %}

create_{{ service }}_user_{{ host }}:
  mysql_user.present:
    - name: {{ service }}
    - password: {{ pillar [service + '_mysql_password'] }}
    - host: {{ address }}
    - connection_unix_socket: /var/run/mysqld/mysqld.sock

grant_{{ service }}_privs_{{ host }}:
   mysql_grants.present:
    - grant: all privileges
    - database: {{ service }}.*
    - user: {{ service }}
    - host: {{ host }}
    - connection_unix_socket: /var/run/mysqld/mysqld.sock

  {% endfor %}
{% endfor %}

