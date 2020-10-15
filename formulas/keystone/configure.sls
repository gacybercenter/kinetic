include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['os_family'] == 'Debian' %}
  {% set webserver = 'apache2' %}
{% elif grains['os_family'] == 'RedHat' %}
  {% set webserver = 'httpd' %}
{% endif %}

{% if grains['spawning'] == 0 %}
  {% set service_conf = pillar['openstack_services']['keystone']['configuration']['endpoints'] %}

init_keystone:
  cmd.run:
    - name: |
        keystone-manage db_sync
        keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
        keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
        keystone-manage bootstrap --bootstrap-password {{ pillar['openstack']['admin_password'] }} \
  {%- for endpoint, attribs in service_conf.items() %}
        --bootstrap-{{ endpoint }}-url {{ attribs['protocol'] }}{{ pillar['endpoints'][endpoint] }}{{ attribs['port'] }}{{ attribs['path'] }} \
  {%- endfor %}
        --bootstrap-region-id RegionOne
    - require:
      - file: /etc/keystone/keystone.conf
      - file: keystone_domain

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

keystone_project_init:
  keystone_project.present:
    - name: service
    - domain: default
    - description: Service Project

keystone_role_init:
  keystone_role.present:
    - name: user

keystone_user_init:
  keystone_user.present:
    - name: keystone
    - domain: default
    - password: {{ pillar ['keystone']['keystone_service_password'] }}

keystone_role_grant:
  keystone_role.present:
    - name: user
    - project: service
    - role: admin

{% else %}

  {% from 'formulas/common/macros/spawn.sls' import check_spawnzero_status with context %}
    {{ check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/openstack/clouds.yml:
  file.managed:
    - source: salt://formulas/common/openstack/files/clouds.yml
    - makedirs: True
    - template: jinja
    - defaults:
        password: {{ pillar['openstack']['admin_password'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['path'] }}

/var/lib/keystone/keystone.db:
  file.absent

/etc/keystone/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/keystone.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://keystone:{{ pillar['keystone']['keystone_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/keystone'
        memcached_servers: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        public_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['port'] }}
        token_expiration: {{ pillar['keystone']['token_expiration'] }}

keystone_domain:
  file.managed:
    - name: /etc/keystone/domains/keystone.{{ pillar['keystone']['ldap_configuration']['keystone_domain'] }}.conf
    - source: salt://formulas/keystone/files/keystone-ldap.conf
    - makedirs: True
    - template: jinja
    - defaults:
        ldap_url: 'url = ldap://{{ pillar ['common_ldap_configuration']['address'] }}'
        ldap_user: 'user = {{ pillar ['common_ldap_configuration']['bind_user'] }}'
        ldap_password: 'password = {{ pillar ['bind_password'] }}'
        ldap_suffix: 'suffix = {{ pillar ['common_ldap_configuration']['base_dn'] }}'
        user_tree_dn: 'user_tree_dn = {{ pillar ['common_ldap_configuration']['user_dn'] }}'
        group_tree_dn: 'group_tree_dn = {{ pillar ['common_ldap_configuration']['group_dn'] }}'
        user_filter: 'user_filter = {{ pillar ['keystone']['ldap_configuration']['user_filter'] }}'
        group_filter: 'group_filter = {{ pillar ['keystone']['ldap_configuration']['group_filter'] }}'
        sql_connection_string: 'connection = mysql+pymysql://keystone:{{ pillar['keystone']['keystone_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/keystone'
        public_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['endpoints']['public']['path'] }}

{% if grains['os_family'] == 'Debian' %}

/etc/apache2/sites-available/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/apache-keystone.conf
    - template: jinja
    - defaults:
        webserver: apache2

webserver_conf:
  file.managed:
    - name: /etc/apache2/apache2.conf
    - source: salt://formulas/keystone/files/apache2.conf
    - template: jinja
    - defaults:
        ServerName: ServerName {{ grains['id'] }}

/usr/local/share/ca-certificates/ldap_ca.crt:
  file.managed:
    - contents_pillar: ldap_ca

update-ca-certificates:
  cmd.run:
    - onchanges:
      - file: /usr/local/share/ca-certificates/ldap_ca.crt

{% elif grains['os_family'] == 'RedHat' %}

/etc/httpd/conf.d/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/apache-keystone.conf
    - template: jinja
    - defaults:
        webserver: httpd

webserver_conf:
  file.managed:
    - name: /etc/httpd/conf/httpd.conf
    - source: salt://formulas/keystone/files/httpd.conf
    - template: jinja
    - defaults:
        ServerName: ServerName {{ grains['id'] }}

/etc/pki/ca-trust/source/anchors/ldap_ca.crt:
  file.managed:
    - contents_pillar: ldap_ca

update-ca-trust extract:
  cmd.run:
    - onchanges:
      - file: /etc/pki/ca-trust/source/anchors/ldap_ca.crt

{% endif %}

/etc/keystone/ldap_ca.crt:
  file.managed:
    - contents_pillar: ldap_ca

/etc/keystone/fernet-keys/0:
  file.managed:
    - contents_pillar: keystone:fernet_primary
    - makedirs: True
    - mode: 600
    - user: keystone
    - group: keystone

/etc/keystone/fernet-keys/1:
  file.managed:
    - contents_pillar: keystone:fernet_secondary
    - makedirs: True
    - mode: 600
    - user: keystone
    - group: keystone

wsgi_service:
  service.running:
    - name: {{ webserver }}
    - enable: True
    - init_delay: 10
    - watch:
      - file: /etc/keystone/keystone.conf
      - file: keystone_domain
      - file: webserver_conf
