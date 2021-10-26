## Copyright 2018 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}
  {% if pillar['hosts']['mysql']['count'] > 1 %}

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
      - file: /bin/galera_recovery

/etc/galera_init_done:
  file.managed:
    - require:
      - cmd: bootstrap_mariadb_start
    - require_in:
      - spawnzero_complete

  {% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

  {% if grains['build_phase'] == 'install' %}
kill_mariadb_for_bootstrap:
  service.dead:
    - name: mariadb
  {% endif %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

fs.file-max:
  sysctl.present:
    - value: 65535

/usr/lib/systemd/system/mariadb.service:
  file.managed:
    - source: salt://formulas/mysql/files/mariadb.service

systemctl daemon-reload:
  cmd.run:
    - onchanges:
      - file: /usr/lib/systemd/system/mariadb.service

/bin/galera_recovery:
  file.managed:
    - source: salt://formulas/mysql/files/galera_recovery

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
{% if pillar['hosts']['mysql']['count'] > 1 %}
        wsrep_on: ON
{% else %}
        wsrep_on: OFF
{% endif %}
        ip_address: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
{% if grains['os_family'] == 'Debian' %}
        wsrep_provider: /usr/lib/libgalera_smm.so
{% elif grains['os_family'] == 'RedHat' %}
        wsrep_provider: /usr/lib64/galera-4/libgalera_smm.so
{% endif %}
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

mariadb_service:
  service.running:
    - name: mariadb
    - enable: true
    - require:
      - file: openstack.conf

{% for service in pillar['openstack_services'] if grains['spawning'] == 0 %}
{% if pillar['openstack_services'][service]['configuration']['dbs'] is defined %}
  {% for host, addresses in salt['mine.get']('role:haproxy', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {% for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}

create_{{ service }}_user_{{ address }}:
  mysql_user.present:
    - name: {{ service }}
    - password: {{ pillar [service][service + '_mysql_password'] }}
    - host: {{ address }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service
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
      {% for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}

grant_{{ service }}_privs_{{ db }}_{{ address }}:
  mysql_grants.present:
    - grant: all privileges
    - database: {{ db }}.*
    - user: {{ service }}
    - host: {{ address }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service
      - mysql_user: create_{{ service }}_user_{{ address }}
      - mysql_database: create_{{ db }}_db

      {% endfor %}
    {% endfor %}
  {% endfor %}
{% endif %}
{% endfor %}

{% for service in pillar['integrated_services'] if grains['spawning'] == 0 %}
{% if pillar['integrated_services'][service]['configuration']['dbs'] is defined %}
  {% for host, addresses in salt['mine.get']('role:haproxy', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
    {% for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}

create_{{ service }}_user_{{ address }}:
  mysql_user.present:
    - name: {{ service }}
    - password: {{ pillar [service][service + '_mysql_password'] }}
    - host: {{ address }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service

    {% endfor %}
  {% endfor %}

  {% for db in pillar['integrated_services'][service]['configuration']['dbs'] %}

create_{{ db }}_db:
  mysql_database.present:
    - name: {{ db }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service

    {% for host, addresses in salt['mine.get']('role:haproxy', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
      {% for address in addresses if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}

    {%if db == 'guacamole' %}
import_schema:
  mysql_query.run_file:
    - query_file: salt://formulas/guacamole/files/initdb.sql
    - database: {{ db }}
    - connection_host: {{ address }}
    - connection_unix_socket: {{ sock }}
    - require:
      - mysql_database: create_{{ db }}_db

    {% endif%}

grant_{{ service }}_privs_{{ db }}_{{ address }}:
  mysql_grants.present:
    - grant: all privileges
    - database: {{ db }}.*
    - user: {{ service }}
    - host: {{ address }}
    - connection_unix_socket: {{ sock }}
    - require:
      - service: mariadb_service
      - mysql_user: create_{{ service }}_user_{{ address }}
      - mysql_database: create_{{ db }}_db

      {% endfor %}
    {% endfor %}
  {% endfor %}
{% endif %}
{% endfor %}

{% if pillar['hosts']['mysql']['count'] > 1 %}
  {% if grains['build_phase'] == 'install' %}
## This is necessary because pc.recovery does not work if mariadbd
## has a clean shutdown.  Making the file immutable ensures that the state
## necessary to perform an automatic recovery is still there
force_recovery:
  module.run:
    - name: file.chattr
    - files:
      - /var/lib/mysql/gvwstate.dat
    - kwargs:
        attributes: i
        operator: add

  {% else %}

force_recovery_removal:
  module.run:
    - name: file.chattr
    - files:
      - /var/lib/mysql/gvwstate.dat
    - kwargs:
        attributes: i
        operator: remove
    - onlyif:
      - lsattr -l /var/lib/mysql/gvwstate.dat | grep -q Immutable
  {% endif %}
{% endif %}
