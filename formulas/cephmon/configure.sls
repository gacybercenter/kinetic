include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/cephmon/install
  - /formulas/ceph/common/configure

{% if grains['spawning'] == 0 %}


spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."
{% endif %}

/tmp/ceph.mon.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-mon-keyring
    - mode: 600
    - user: ceph
    - group: ceph

/etc/ceph/ceph.client.admin.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-admin-keyring

/etc/ceph/ceph.client.images.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-images-keyring

/etc/ceph/ceph.client.volumes.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-volumes-keyring

/etc/ceph/ceph.client.compute.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-compute-keyring

/etc/ceph/ceph.client.manila.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-client-manila-keyring

/var/lib/ceph/bootstrap-osd/ceph.keyring:
  file.managed:
    - contents_pillar: ceph:ceph-keyring

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

fs.file-max:
  sysctl.present:
    - value: 500000

/etc/security/limits.conf:
  file.managed:
    - source: salt://formulas/cephmon/files/limits.conf

ceph auth import -i /etc/ceph/ceph.client.images.keyring:
  cmd.run:
    - onchanges:
      - /etc/ceph/ceph.client.images.keyring
    - require:
      - service: ceph-mon@{{ grains['id'] }}

ceph auth import -i /etc/ceph/ceph.client.volumes.keyring:
  cmd.run:
    - onchanges:
      - /etc/ceph/ceph.client.volumes.keyring
    - require:
      - service: ceph-mon@{{ grains['id'] }}

ceph auth import -i /etc/ceph/ceph.client.compute.keyring:
  cmd.run:
    - onchanges:
      - /etc/ceph/ceph.client.compute.keyring
    - require:
      - service: ceph-mon@{{ grains['id'] }}

{% if grains['spawning'] == 0 and salt['grains.get']('production', False) == True  %}
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
