include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/ceph/common/configure

{% if grains['spawning'] == 0 %}

  {% from 'formulas/common/macros/spawn.sls' import spawnzero_complete with context %}
    {{ spawnzero_complete() }}

{% else %}

  {% from 'formulas/common/macros/spawn.sls' import check_spawnzero_status with context %}
    {{ check_spawnzero_status(grains['type']) }}

{% endif %}

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
      - sls: /formulas/ceph/common/configure
