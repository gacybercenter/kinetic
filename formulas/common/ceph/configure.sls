## Copyright 2020 Augusta University
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

{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

/etc/ceph/ceph.conf:
  file.managed:
    - source: salt://formulas/common/ceph/files/ceph.conf
    - template: jinja
    - makedirs: True
    - defaults:
        fsid: {{ pillar['ceph']['fsid'] }}
        mon_members: |
          mon host =
          {%- for host, addresses in salt['mine.get']('role:cephmon', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['sfe']) -%}
                {{ " "+address }}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        mds_members: |
          {% for host, address in salt['mine.get']('role:mds', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          [mds.{{ host }}]
          host = {{ host }}
          keyring = /var/lib/ceph/mds/ceph-{{ host }}/keyring

          {% endfor %}
        swift_members: |
          {% for host, address in salt['mine.get']('role:swift', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          [client.{{ host }}]
          host = {{ host }}
          keyring = /etc/ceph/ceph.client.{{ host }}.keyring
          rgw_keystone_url = {{ constructor.endpoint_url_constructor(project='keystone', service='keystone', endpoint='internal', base=True) }}
          rgw keystone api version = 3
          rgw keystone admin user = swift
          rgw keystone admin password = {{ pillar ['swift']['swift_service_password'] }}
          rgw keystone admin project = service
          rgw keystone admin domain = default
          rgw keystone accepted roles = admin,user
          rgw keystone token cache size = 10
          rgw keystone revocation interval = 300
          rgw keystone implicit tenants = true
          rgw swift account in url = true
          rgw swift url prefix = swift
          rgw trust forwarded https = true

          {% endfor %}
        manila_members: |
          {% for host, address in salt['mine.get']('role:share', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          [client.{{ host }}]
          client mount uid = 0
          client mount gid = 0
          log file = /var/log/ceph/ceph-client.manila.log
          admin socket = /opt/ceph-$name.$pid.asok
          keyring = /etc/ceph/ceph.client.{{ host }}.keyring

          {% endfor %}
        sfe_network: {{ pillar['networking']['subnets']['sfe'] }}
        sbe_network: {{ pillar['networking']['subnets']['sbe'] }}
