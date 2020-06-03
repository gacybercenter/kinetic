{% if grains['os_family'] == 'Debian' %}

ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph Octopus
    - name: deb https://download.ceph.com/debian-octopus/ focal main
    - file: /etc/apt/sources.list.d/ceph.list
    - key_url: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - ceph_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

centos-release-ceph-octopus:
  pkg.installed

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkg: centos-release-ceph-octopus

{% endif %}
