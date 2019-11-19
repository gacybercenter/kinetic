{% if grains['os_family'] == 'Debian' %}

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

{% elif grains['os_family'] == 'RedHat' %}

ceph_repo:
  pkgrepo.managed:
    - humanname: Ceph Nautilus
    - name: ceph
    - baseurl: https://download.ceph.com/rpm-nautilus/el7/$basearch
    - file: /etc/yum.repos.d/ceph.repo
    - gpgkey: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - ceph_repo

{% endif %}
