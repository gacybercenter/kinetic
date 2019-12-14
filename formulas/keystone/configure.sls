include:
  - formulas/keystone/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/keystone/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/keystone.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://keystone:{{ pillar['keystone']['keystone_mysql_password'] }}@{{ address[0] }}/keystone'
{% endfor %}
        memcached_servers: |
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}:11211
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        public_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}

{% if grains['os_family'] == 'Debian' %}

/etc/apache2/sites-available/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/apache-keystone.conf
    - template: jinja
    - defaults:
        webserver: apache2

{% elif grains['os_family'] == 'RedHat' %}

/etc/httpd/conf.d/keystone.conf:
  file.managed:
    - source: salt://formulas/keystone/files/apache-keystone.conf
    - template: jinja
    - defaults:
        webserver: httpd

{% endif %}

{% set keystone_domain = pillar['keystone_ldap_configuration']['keystone_domain'] %}
/etc/keystone/domains/keystone.{{ keystone_domain }}.conf:
  file.managed:
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
        user_filter: 'user_filter = {{ pillar ['keystone_ldap_configuration']['user_filter'] }}'
        group_filter: 'group_filter = {{ pillar ['keystone_ldap_configuration']['group_filter'] }}'
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://keystone:{{ pillar['keystone']['keystone_mysql_password'] }}@{{ address[0] }}/keystone'
{% endfor %}
        public_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}

initialize_keystone:
  cmd.script:
    - source: salt://formulas/keystone/files/initialize.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        public_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        admin_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['keystone']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['admin_endpoint']['path'] }}

{% if grains['os_family'] == 'Debian' %}

/etc/apache2/apache2.conf:
  file.managed:
    - source: salt://formulas/keystone/files/apache2.conf
    - template: jinja
    - defaults:
        ServerName: ServerName {{ grains['id'] }}

{% elif grains['os_family'] == 'RedHat' %}

/etc/httpd/conf/httpd.conf:
  file.managed:
    - source: salt://formulas/keystone/files/httpd.conf
    - template: jinja
    - defaults:
        ServerName: ServerName {{ grains['id'] }}

{% endif %}

/etc/keystone/ldap_ca.crt:
  file.managed:
    - contents_pillar: ldap_ca

{% if grains['os_family'] == 'Debian' %}

/usr/local/share/ca-certificates/ldap_ca.crt:
  file.managed:
    - contents_pillar: ldap_ca

update-ca-certificates:
  cmd.run:
    - onchanges:
      - file: /usr/local/share/ca-certificates/ldap_ca.crt

{% elif grains['os_family'] == 'RedHat' %}

/etc/pki/ca-trust/source/anchors/ldap_ca.crt:
  file.managed:
    - contents_pillar: ldap_ca

update-ca-trust extract:
  cmd.run:
    - onchanges:
      - file: /etc/pki/ca-trust/source/anchors/ldap_ca.crt

{% endif %}

project_init:
  cmd.script:
    - source: salt://formulas/keystone/files/project_init.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        keystone_service_password: {{ pillar ['keystone']['keystone_service_password'] }}
        keystone_domain: {{ keystone_domain }}
{% if grains['os_family'] == 'Debian' %}
        webserver: apache2
{% elif grains['os_family'] == 'RedHat' %}
        webserver: httpd
{% endif %}
    - creates:
      - /etc/keystone/projects_done

{% if grains['os_family'] == 'Debian' %}
systemctl restart apache2.service && sleep 10:
  cmd.run:
    - prereq:
      - cmd: project_init

apache2_service:
  service.running:
    - name: apache2
    - enable: True
    - watch:
      - file: /etc/keystone/keystone.conf
      - file: /etc/keystone/domains/keystone.{{ keystone_domain }}.conf
      - file: /etc/apache2/apache2.conf

{% elif grains['os_family'] == 'RedHat' %}

systemctl restart httpd.service && sleep 10:
  cmd.run:
    - prereq:
      - cmd: project_init

httpd_service:
  service.running:
    - name: httpd
    - enable: True
    - watch:
      - file: /etc/keystone/keystone.conf
      - file: /etc/keystone/domains/keystone.{{ keystone_domain }}.conf
      - file: /etc/httpd/conf/httpd.conf

{% endif %}

/var/lib/keystone/keystone.db:
  file.absent
