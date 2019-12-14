include:
  - formulas/mysql/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

systemctl start mariadb.server --wsrep-new-cluster && touch /etc/galera_init_done:
  cmd.run:
    - creates: /etc/galera_init_done
    - require:
      - file: openstack.conf

{% endif %}

openstack.conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
{% set sock = "/var/run/mysqld/mysqld.sock" %}
    - name: /etc/mysql/mariadb.conf.d/99-openstack.cnf
{% elif grains['os_family'] == 'RedHat' %}
{% set sock = "/var/lib/mysql/mysql.sock" %}
    - name: /etc/my.cnf.d/openstack.cnf
{% endif %}
    - source: salt://formulas/mysql/files/openstack.conf
    - makedirs: True
    - template: jinja
    - defaults:
        ip_address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        wsrep_cluster_address: |-
          gcomm://
          {%- for host, addresses in salt['mine.get']('role:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
                {{ address }}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        wsrep_cluster_name: {{ pillar['mysql']['wsrep_cluster_name'] }}
    - require:
      - sls: formulas/mysql/install

mariadb_service:
  service.running:
    - name: mariadb
    - enable: True
    - watch:
      - file: openstack.conf

{% if grains['os_family'] == 'RedHat' %}
set_unix_socket_root:
  mysql_query.run:
    - database: mysql
    - query: "update mysql.user set plugin = 'unix_socket' where user = 'root';"
    - output: "/root/.socket_assignment"
    - require:
      - service: mariadb_service
    - unless:
      - test -e /root/.socket_assignment
{% endif %}

{% for service in pillar['openstack_services'] %}
  {% for db in pillar['openstack_services'][service]['configuration']['dbs'] %}

create_{{ db }}_db:
  mysql_database.present:
    - name: {{ db }}
    - connection_unix_socket: {{ sock }}

  {% endfor %}
  {% for host, address in salt['mine.get']('type:'+service, 'network.ip_addrs', tgt_type='grain') | dictsort() %}

create_{{ service }}_user_{{ host }}:
  mysql_user.present:
    - name: {{ service }}
    - password: {{ pillar [service][service + '_mysql_password'] }}
    - host: {{ address[0] }}
    - connection_unix_socket: {{ sock }}

    {% for db in pillar['openstack_services'][service]['configuration']['dbs'] %}

grant_{{ service }}_privs_{{ host }}_{{ db }}:
   mysql_grants.present:
    - grant: all privileges
    - database: {{ db }}.*
    - user: {{ service }}
    - host: {{ address[0] }}
    - connection_unix_socket: {{ sock }}

      {% if db == 'zun' %}
        {% for host, address in salt['mine.get']('type:container', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
create_{{ service }}_user_{{ host }}:
  mysql_user.present:
    - name: {{ service }}
    - password: {{ pillar [service][service + '_mysql_password'] }}
    - host: {{ address[0] }}
    - connection_unix_socket: {{ sock }}

grant_{{ service }}_privs_{{ host }}_{{ db }}:
   mysql_grants.present:
    - grant: all privileges
    - database: {{ db }}.*
    - user: {{ service }}
    - host: {{ address[0] }}
    - connection_unix_socket: {{ sock }}
        {% endfor %}
      {% endif %}

      {% if db == 'manila' %}
        {% for host, address in salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
create_{{ service }}_user_{{ host }}:
  mysql_user.present:
    - name: {{ service }}
    - password: {{ pillar [service][service + '_mysql_password'] }}
    - host: {{ address[0] }}
    - connection_unix_socket: {{ sock }}

grant_{{ service }}_privs_{{ host }}_{{ db }}:
   mysql_grants.present:
    - grant: all privileges
    - database: {{ db }}.*
    - user: {{ service }}
    - host: {{ address[0] }}
    - connection_unix_socket: {{ sock }}
        {% endfor %}
      {% endif %}
    {% endfor %}
  {% endfor %}
{% endfor %}
