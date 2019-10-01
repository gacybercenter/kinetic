include:
  - /formulas/glance/install
  - formulas/common/base
  - formulas/common/networking
  - formulas/ceph/common/configure

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
    - mode: 644

{% if grains['spawning'] == 0 %}

make_glance_service:
  cmd.script:
    - source: salt://formulas/glance/files/mkservice.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
        glance_internal_endpoint: {{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['internal_endpoint']['path'] }}
        glance_public_endpoint: {{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['public_endpoint']['path'] }}
        glance_admin_endpoint: {{ pillar ['openstack_services']['glance']['configuration']['admin_endpoint']['protocol'] }}{{ pillar['endpoints']['admin'] }}{{ pillar ['openstack_services']['glance']['configuration']['admin_endpoint']['port'] }}{{ pillar ['openstack_services']['glance']['configuration']['admin_endpoint']['path'] }}
        glance_service_password: {{ pillar ['glance']['glance_service_password'] }}

glance-manage db_sync:
  cmd.run:
    - runas: glance
    - require:
      - file: /etc/glance/glance-api.conf
    - unless:
      - glance-manage db check

make_images_pool:
  event.send:
    - name: create/{{ grains['type'] }}/pool
    - data:
        pgs: {{ pillar['cephconf']['images_pgs'] }}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/glance/glance-api.conf:
  file.managed:
    - source: salt://formulas/glance/files/glance-api.conf
    - template: jinja
    - defaults:
{% for server, address in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        sql_connection_string: 'connection = mysql+pymysql://glance:{{ pillar['glance']['glance_mysql_password'] }}@{{ address[0] }}/glance'
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['glance']['glance_service_password'] }}

glance_api_service:
  service.running:
    - name: glance-api
    - watch:
      - file: /etc/glance/glance-api.conf
