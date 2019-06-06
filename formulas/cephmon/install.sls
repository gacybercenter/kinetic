spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph Nautilus
    - name: deb https://download.ceph.com/debian-nautilus/ bionic main
    - file: /etc/apt/sources.list.d/ceph.list
    - key_url: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - ceph_repo
    - dist_upgrade: True

install_ceph:
  pkg.installed:
    - name: ceph
    - require: 
      - pkgrepo: ceph_repo
