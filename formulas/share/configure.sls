include:
  - formulas/share/install
  - formulas/common/base
  - formulas/common/networking
  - formulas/ceph/common/configure

{% if grains['spawning'] == 0 %}

make_filesystem:
  event.send:
    - name: create/manila/filesystem
    - data:
        metadata_pgs: {{ pillar['cephconf']['fileshare_metadata_pgs'] }}
        data_pgs: {{ pillar['cephconf']['fileshare_data_pgs'] }}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/var/lib/manila/tmp:
  file.directory:
    - makedirs: true
    - user: manila
    - group: manila

/etc/ceph/ceph.client.manila.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-manila-keyring
    - mode: 640
    - user: root
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
          [cephfsnfs-{{ grains['id'] }}]
          ganesha_rados_store_enable = True
          ganesha_rados_store_pool_name = fileshare_data
          driver_handles_share_servers = False
          share_backend_name = CEPHFSNFS-{{ grains['id'] }}
          share_driver = manila.share.drivers.cephfs.driver.CephFSDriver
          cephfs_conf_path = /etc/ceph/ceph.conf
          cephfs_protocol_helper_type = NFS
          cephfs_auth_id = manila
          cephfs_cluster_name = ceph
          cephfs_enable_snapshots = True
          cephfs_ganesha_server_is_remote = False
          cephfs_ganesha_server_ip = {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['public'])[0] }}

manila_share_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: manila-share
{% elif grains['os_family'] == 'RedHat' %}
    - name: openstack-manila-share
{% endif %}
    - enable: true
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
    - watch:
      - file: /etc/manila/manila.conf
