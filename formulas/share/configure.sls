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

{% endif %}

/var/lock/manila:
  file.directory:
    - makedirs: true
    - user: manila
    - group: manila

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
    - group: ceph

/etc/manila/manila.conf:
  file.managed:
    - source: salt://formulas/share/files/manila.conf
    - template: jinja
    - defaults:
{% for server, addresses in salt['mine.get']('type:mysql', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        sql_connection_string: 'connection = mysql+pymysql://manila:{{ pillar['manila']['manila_mysql_password'] }}@{{ address }}/manila'
    {%- endif -%}
  {%- endfor -%}
{% endfor %}
{% for server, addresses in salt['mine.get']('type:rabbitmq', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        transport_url: rabbit://openstack:{{ pillar['rabbitmq']['rabbitmq_password'] }}@{{ address }}
    {%- endif -%}
  {%- endfor -%}
{% endfor %}
        www_authenticate_uri: {{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['protocol'] }}{{ pillar['endpoints']['public'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['public_endpoint']['path'] }}
        auth_url: {{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['protocol'] }}{{ pillar['endpoints']['internal'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['port'] }}{{ pillar ['openstack_services']['keystone']['configuration']['internal_endpoint']['path'] }}
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        password: {{ pillar['manila']['manila_service_password'] }}
        my_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
{% for server, addresses in salt['mine.get']('type:share', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['public']) %}
        ganesha_ip: {{ address }}
    {%- endif -%}
  {%- endfor -%}
{% endfor %}

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
