include:
  - /formulas/glance/install
  - formulas/common/base
  - formulas/common/networking

/etc/ceph/ceph.client.images.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-images-keyring
    - mode: 640
    - user: root
    - group: glance

ceph_user_exists:
  user.present:
    - name: ceph
    - home: /etc/ceph

/etc/sudoers.d/ceph:
  file.managed:
    - contents:
      - ceph ALL = (root) NOPASSWD:ALL
      - Defaults:ceph !requiretty
    - file_mode: 644

make_glance_service:
  cmd.script:
    - source: salt://formulas/glance/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        internal_endpoint: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
        public_endpoint: {{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['path'] }}
        admin_endpoint: {{ pillar ['openstack_services']['glance']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['glance']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['admin_endpoint']['path'] }}
        glance_service_password: {{ pillar ['glance']['glance_service_password'] }}

/etc/glance/glance-api.conf:
  file.managed:
    - source: salt://formulas/glance/files/glance-api.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://glance:{{ pillar['glance']['glance_mysql_password'] }}@{{ address[0] }}/glance'
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['glance_service_password'] }}

/etc/glance/glance-registry.conf:
  file.managed:
    - source: salt://formulas/glance/files/glance-registry.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://glance:{{ pillar['glance']['glance_mysql_password'] }}@{{ address[0] }}/glance'
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints'$
        auth_url: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['interna$
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['glance_service_password'] }}

/bin/sh -c "glance-manage db_sync" glance:
  cmd.run

glance_registry_service:
  service.running:
    - name: glance-registry
    - watch:
      - file: /etc/glance/glance-registry.conf

glance_api_service:
  service.running:
    - name: glance-api
    - watch:
      - file: /etc/glance/glance-api.conf
