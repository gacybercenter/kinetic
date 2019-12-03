include:
  - formulas/common/base
  - formulas/common/networking
  - formulas/cephmon/install
  - formulas/ceph/common/configure

{% if grains['spawning'] == 0 %}
spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."
{% endif %}

ceph_user_exists:
  user.present:
    - name: ceph
    - home: /etc/ceph

/etc/sudoers.d/ceph:
  file.managed:
    - contents:
      - ceph ALL = (root) NOPASSWD:ALL
      - Defaults:ceph !requiretty
    - mode: 644

/var/lib/ceph/mds/ceph-{{ grains['id'] }}:
  file.directory:
    - user: ceph
    - group: ceph

get_adminkey:
  file.managed:
    - name: /etc/ceph/ceph.client.admin.keyring
    - contents_pillar: ceph:ceph-client-admin-keyring
    - mode: 600
    - user: root
    - group: root
    - prereq:
      - cmd: make_{{ grains['id'] }}_mdskey

make_{{ grains['id'] }}_mdskey:
  cmd.run:
    - name: ceph auth get-or-create mds.{{ grains['id'] }} mon 'profile mds' mgr 'profile mds' mds 'allow *' osd 'allow *' -o /var/lib/ceph/mds/ceph-{{ grains['id'] }}/keyring
    - creates:
      - /var/lib/ceph/mds/ceph-{{ grains['id'] }}/keyring

wipe_adminkey:
  file.absent:
    - name: /etc/ceph/ceph.client.admin.keyring

ceph-mds@{{ grains['id'] }}:
  service.running:
    - enable: true
    - watch:
      - sls: formulas/ceph/common/configure
