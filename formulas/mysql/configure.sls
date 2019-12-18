include:
  - formulas/mysql/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}
  {% if pillar['virtual']['mysql']['count'] > 1 %}

/bin/galera_new_cluster:
  file.managed:
    - source: salt://formulas/mysql/files/galera_new_cluster
    - require_in:
      - cmd: bootstrap_mariadb_start

bootstrap_mariadb_dead:
  service.dead:
    - name: mariadb
    - prereq:
      - cmd: bootstrap_mariadb_start

bootstrap_mariadb_start:
  cmd.run:
    - name: galera_new_cluster
    - creates: /etc/galera_init_done
    - require:
      - file: openstack.conf

/etc/galera_init_done:
  file.managed:
    - require:
      - cmd: bootstrap_mariadb_start

master_reboot_pause:
  module.run:
    - name: test.sleep
    - length: 300
    - onchanges:
      - grains: cluster_established_final
    - order: last
  {% endif %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."
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
        wsrep_cluster_name: {{ pillar['mysql']['wsrep_cluster_name'] }}
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
    - require:
      - sls: formulas/mysql/install

mariadb_service:
  service.running:
    - name: mariadb
    - enable: true
    - retry:
        attempts: 5
        until: True
        interval: 60
{% if salt['grains.get']('production', False) == True %}
        watch:
          - file: openstack.conf
{% endif %}

{% if salt['grains.get']('cluster_established', False) == True %}

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
    - require:
      - service: mariadb_service
  {% endif %}

  {% for service in pillar['openstack_services'] %}
    {% for host, addresses in salt['mine.get']('role:haproxy', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
      {% for address in addresses %}
        {% if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}

create_{{ service }}_user_{{ address }}:
  mysql_user.present:
    - name: {{ service }}
    - password: {{ pillar [service][service + '_mysql_password'] }}
    - host: {{ address }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service

        {% endif %}
      {% endfor %}
    {% endfor %}

    {% for db in pillar['openstack_services'][service]['configuration']['dbs'] %}

create_{{ db }}_db:
  mysql_database.present:
    - name: {{ db }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service

      {% for host, addresses in salt['mine.get']('role:haproxy', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        {% for address in addresses %}
          {% if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}

grant_{{ service }}_privs_{{ db }}_{{ address }}:
   mysql_grants.present:
    - grant: all privileges
    - database: {{ db }}.*
    - user: {{ service }}
    - host: {{ address }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service
      - mysql_user: create_{{ service }}_user
      - mysql_database: create_{{ db }}_db

          {% endif %}
        {% endfor %}
      {% endfor %}

    {% endfor %}
  {% endfor %}
{% endif %}

cluster_established_final:
  grains.present:
    - name: cluster_established
    - value: True
    - require:
      - service: mariadb_service
