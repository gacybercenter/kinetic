include:
  - formulas/share/install
  - formulas/common/base
  - formulas/common/networking
  - formulas/ceph/common/configure

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

make_filesystem:
  event.send:
    - name: create/manila/filesystem
    - data:
        metadata_pgs: {{ pillar['cephconf']['fileshare_metadata_pgs'] }}
        data_pgs: {{ pillar['cephconf']['fileshare_data_pgs'] }}

make_nfs_share_type:
  cmd.script:
    - source: salt://formulas/share/files/mknfs.sh
    - template: jinja
    - defaults:
        admin_password: {{ pillar['openstack']['admin_password'] }}
        keystone_internal_endpoint: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
    - require:
      - service: manila_share_service
      - service: nfs_ganesha_service
    - retry:
        attempts: 3
        interval: 10

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
        enabled_share_backends: |-
          enabled_share_backends =
          {%- if salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain')|length -%}
          {%- for server, addresses in salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
          {%- set outerloop = loop -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['public']) -%}
          cephfsnfs{{ outerloop.index }}
              {%- endif -%}
            {%- endfor -%}
          {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
          {%- else -%}
          cephfsnfs0
          {%- endif %}
        shares: |-
          {{ ""|indent(10) }}
          {%- if salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain')|length -%}
          {%- for server, addresses in salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
          {%- set outerloop = loop -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['public']) -%}
          [cephfsnfs{{ outerloop.index }}]
          driver_handles_share_servers = False
          share_backend_name = CEPHFSNFS{{ outerloop.index }}
          share_driver = manila.share.drivers.cephfs.driver.CephFSDriver
          cephfs_conf_path = /etc/ceph/ceph.conf
          cephfs_protocol_helper_type = NFS
          cephfs_auth_id = manila
          cephfs_cluster_name = ceph
          cephfs_enable_snapshots = True
          cephfs_ganesha_server_is_remote = False
          cephfs_ganesha_server_ip = {{ address }}
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %}
          {%- else -%}
          [cephfsnfs0]
          {%- endif %}

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
