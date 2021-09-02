## Copyright 2018 Augusta University
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
  - /formulas/common/ceph/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

/etc/ceph/ceph.mon.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-mon-keyring
    - mode: "0600"
    - user: ceph
    - group: ceph

/var/lib/ceph/bootstrap-osd/ceph.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-keyring

{% for client_keyring in ['admin', 'images', 'volumes', 'compute'] %}
/etc/ceph/ceph.client.{{ client_keyring }}.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-{{ client_keyring }}-keyring
{% endfor %}

/var/lib/ceph/mon/ceph-{{ grains['id'] }}:
  file.directory:
    - user: ceph
    - group: ceph
    - recurse:
      - user
      - group

monmaptool --create --clobber --fsid {{ pillar['ceph']['fsid'] }} /etc/ceph/monmap:
  cmd.run:
    - creates:
      - /etc/ceph/monmap

{% for host, addresses in salt['mine.get']('role:cephmon', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['sfe']) %}
monmaptool --addv {{ host }} [v1:{{ address }}:6789,v2:{{ address }}:3300] /etc/ceph/monmap:
  cmd.run:
    - unless:
      - monmaptool --print /etc/ceph/monmap | grep -q {{ host }}
    {%- endif -%}
  {%- endfor -%}
{% endfor %}

ceph-mon --cluster ceph --mkfs -i {{ grains['id'] }} --monmap /etc/ceph/monmap --keyring /etc/ceph/ceph.mon.keyring && touch /var/lib/ceph/mon/ceph-{{ grains['id'] }}/done:
  cmd.run:
    - runas: ceph
    - require:
      - /var/lib/ceph/mon/ceph-{{ grains['id'] }}
    - creates:
      - /var/lib/ceph/mon/ceph-{{ grains['id'] }}/done

ceph-mon@{{ grains['id'] }}:
  service.running:
    - enable: true
    - watch:
      - sls: /formulas/common/ceph/configure

/var/lib/ceph/mgr/ceph-{{ grains['id'] }}:
  file.directory:
    - user: ceph
    - group: ceph

ceph auth get-or-create mgr.{{ grains['id'] }} mon 'allow profile mgr' osd 'allow *' mds 'allow *' > /var/lib/ceph/mgr/ceph-{{ grains['id'] }}/keyring:
  cmd.run:
    - creates:
      - /var/lib/ceph/mgr/ceph-{{ grains['id'] }}/keyring

ceph-mgr@{{ grains['id'] }}:
  service.running:
    - enable: true
    - watch:
      - cmd: ceph auth get-or-create mgr.{{ grains['id'] }} mon 'allow profile mgr' osd 'allow *' mds 'allow *' > /var/lib/ceph/mgr/ceph-{{ grains['id'] }}/keyring
      - sls: /formulas/common/ceph/configure

fs.file-max:
  sysctl.present:
    - value: 500000

/etc/security/limits.conf:
  file.managed:
    - source: salt://formulas/cephmon/files/limits.conf

{% for auth in ['images', 'volumes', 'compute', 'crash'] %}
ceph auth import -i /etc/ceph/ceph.client.{{ auth }}.keyring:
  cmd.run:
    - onchanges:
      - /etc/ceph/ceph.client.{{ auth }}.keyring
    - require:
      - service: ceph-mon@{{ grains['id'] }}
{% endfor %}

{% if grains['spawning'] == 0 %}
  {% for pool in ['images', 'volumes', 'vms', 'fileshare_data', 'fileshare_metadata'] %}
ceph osd pool create {{ pool }} 1:
  cmd.run:
    - unless:
      - ceph osd pool get {{ pool }} size
    {% if pool in ['images', 'vms', 'volumes'] %}
ceph osd pool application enable {{ pool }} rbd:
  cmd.run:
    - unless:
      - ceph osd pool application get {{ pool }} | grep -q rbd
    {% endif %}
  {% endfor %}
  {% if salt['pillar.get']('hosts:manila:enabled', 'False') == True %}
ceph fs new manila fileshare_metadata fileshare_data:
  cmd.run:
    - unless:
      - ceph fs get manila
  {% endif %}
{% endif %}

#set the global osd pool default autoscale to off if VMs pool does not have it.
#checking the VMs pool status as the gloabl status data is not available
ceph config set global osd_pool_default_pg_autoscale_mode off:
  cmd.run:
    - unless:
      - ceph osd pool get vms pg_autoscale_mode |grep -q off
