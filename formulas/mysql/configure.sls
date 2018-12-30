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
