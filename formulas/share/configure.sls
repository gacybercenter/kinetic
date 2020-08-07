include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/ceph/common/configure

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - name: mine.send
    - m_name: spawnzero_complete
    - kwargs:
        mine_function: grains.item
    - args:
      - spawnzero_complete
    - onchanges:
      - grains: spawnzero_complete

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

get_adminkey:
  file.managed:
    - name: /etc/ceph/ceph.client.admin.keyring
    - contents_pillar: ceph:ceph-client-admin-keyring
    - mode: 600
    - user: root
    - group: root
    - prereq:
      - cmd: make_{{ grains['id'] }}_manilakey

make_{{ grains['id'] }}_manilakey:
  cmd.run:
    - name: ceph auth get-or-create client.{{ grains['id'] }} mds 'allow *' osd 'allow rw' mon 'allow r, allow command "auth del", allow command "auth caps", allow command "auth get", allow command "auth get-or-create"' -o /etc/ceph/ceph.client.{{ grains['id'] }}.keyring
    - creates:
      - /etc/ceph/ceph.client.{{ grains['id'] }}.keyring

wipe_adminkey:
  file.absent:
    - name: /etc/ceph/ceph.client.admin.keyring

/etc/ceph/ceph.client.{{ grains['id'] }}.keyring:
  file.managed:
    - mode: 640
    - user: root
    - group: manila

/var/lib/manila/tmp:
  file.directory:
    - makedirs: true
    - user: manila
    - group: manila

/etc/manila/manila.conf:
  file.managed:
    - source: salt://formulas/share/files/manila.conf
    - template: jinja
    - defaults:
        sql_connection_string: 'connection = mysql+pymysql://manila:{{ pillar['manila']['manila_mysql_password'] }}@{{ pillar['haproxy']['dashboard_domain'] }}/manila'
        transport_url: |-
          rabbit://
          {%- for host, addresses in salt['mine.get']('role:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
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
        password: {{ pillar['manila']['manila_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        shares: |-
          [cephfsnfs{{ grains['spawning'] }}]
          ganesha_rados_store_enable = True
          ganesha_rados_store_pool_name = fileshare_data
          driver_handles_share_servers = False
          share_backend_name = CEPHFSNFS{{ grains['spawning'] }}
          share_driver = manila.share.drivers.cephfs.driver.CephFSDriver
          cephfs_conf_path = /etc/ceph/ceph.conf
          cephfs_protocol_helper_type = NFS
          cephfs_auth_id = {{ grains['id'] }}
          cephfs_cluster_name = ceph
          cephfs_enable_snapshots = True
          cephfs_ganesha_server_is_remote = False
          cephfs_ganesha_server_ip = {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        backend: cephfsnfs{{ grains['spawning'] }}

manila_share_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: manila-share
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-manila-share
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - watch:
      - file: /etc/manila/manila.conf

nfs_ganesha_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: nfs-ganesha
{% elif grains['os_family'] == 'RedHat' %}
    - name: nfs-ganesha
{% endif %}
    - enable: true
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - watch:
      - file: /etc/manila/manila.conf
