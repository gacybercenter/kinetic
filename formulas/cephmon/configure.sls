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

/tmp/ceph.mon.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-mon-keyring
    - mode: 600
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

monmaptool --create --clobber --fsid {{ pillar['ceph']['fsid'] }} /tmp/monmap:
  cmd.run:
    - creates:
      - /tmp/monmap

{% for host, addresses in salt['mine.get']('role:cephmon', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
  {%- for address in addresses -%}
    {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['sfe']) %}
monmaptool --addv {{ host }} [v1:{{ address }}:6789,v2:{{ address }}:3300] /tmp/monmap:
  cmd.run:
    - unless:
      - monmaptool --print /tmp/monmap | grep -q {{ host }}
    {%- endif -%}
  {%- endfor -%}
{% endfor %}

ceph-mon --cluster ceph --mkfs -i {{ grains['id'] }} --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring && touch /var/lib/ceph/mon/ceph-{{ grains['id'] }}/done:
  cmd.run:
    - runas: ceph
    - requires:
      - /var/lib/ceph/mon/ceph-{{ grains['id'] }}
    - creates:
      - /var/lib/ceph/mon/ceph-{{ grains['id'] }}/done

ceph-mon@{{ grains['id'] }}:
  service.running:
    - enable: true
    - watch:
      - sls: /formulas/ceph/common/configure

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
      - sls: /formulas/ceph/common/configure

fs.file-max:
  sysctl.present:
    - value: 500000

/etc/security/limits.conf:
  file.managed:
    - source: salt://formulas/cephmon/files/limits.conf

{% for auth in ['images', 'volumes', 'compute'] %}
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
  {% endfor %}
ceph fs new manila fileshare_metadata fileshare_data:
  cmd.run:
    - unless:
      - ceph fs get manila
{% endif %}
