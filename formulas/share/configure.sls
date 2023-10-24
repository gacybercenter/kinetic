## Copyright 2019 Augusta University
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
  - /formulas/common/fluentd/configure
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{% if pillar['cephconf']['autoscale'] == 'off' %}
make_filesystem:
  event.send:
    - name: set/manila/pool_pgs
    - data:
        metadata_pgs: {{ pillar['cephconf']['fileshare_metadata_pgs'] }}
        data_pgs: {{ pillar['cephconf']['fileshare_data_pgs'] }}
{% endif %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

get_adminkey:
  file.managed:
    - name: /etc/ceph/ceph.client.admin.keyring
    - contents_pillar: ceph:ceph-client-admin-keyring
    - mode: "0600"
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
    - mode: "0640"
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
        transport_url: {{ constructor.rabbitmq_url_constructor() }}
        sql_connection_string: {{ constructor.mysql_url_constructor(user='manila', database='manila') }}
        www_authenticate_uri: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='public') }}
        auth_url: {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal') }}
        memcached_servers: {{ constructor.memcached_url_constructor() }}
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
