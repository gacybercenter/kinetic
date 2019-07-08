include:
  - formulas/common/base
  - formulas/common/networking
  - formulas/cephmon/install
  - formulas/ceph/common/configure

networking_mine_update_ceph:
  module.run:
    - name: mine.update
    - require:
      - sls: formulas/cephmon/install
  event.send:
    - name: {{ grains['type'] }}/mine/address/update
    - data: "{{ grains['type'] }} mine has been updated."
  
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

{% for host, address in salt['mine.get']('role:swift', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
ceph auth get client.swift.{{ host }} > /etc/ceph/ceph.client.swift.keyring:
  cmd.run
{% endfor %}

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

monmaptool --create --generate --clobber -c /etc/ceph/ceph.conf /tmp/monmap:
  cmd.run:
    - creates:
      - /tmp/monmap

ceph-mon --cluster ceph --mkfs -i {{ grains['id'] }} --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring && touch /var/lib/ceph/mon/ceph-{{ grains['id'] }}/done:
  cmd.run:
    - runas: ceph
    - requires:
      - /var/lib/ceph/mon/ceph-{{ grains['id'] }}
    - creates:
      - /var/lib/ceph/mon/ceph-{{ grains['id'] }}/done

ceph-mon@{{ grains['id'] }}:
  service.running:
    - watch:
      - sls: formulas/ceph/common/configure

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
