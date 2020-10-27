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

ceph_repo:
  pkgrepo.managed:
    - name: ceph
    - baseurl: https://download.ceph.com/rpm-octopus/el8/$basearch
    - file: /etc/yum.repos.d/ceph.repo
    - gpgkey: https://download.ceph.com/keys/release.asc

## new requirement with octopus+el8
ceph_repo_noarch:
  pkgrepo.managed:
    - name: ceph_noarch
    - baseurl: https://download.ceph.com/rpm-octopus/el8/noarch
    - file: /etc/yum.repos.d/ceph_noarch.repo
    - gpgkey: https://download.ceph.com/keys/release.asc

update_packages_ceph:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: ceph_repo
      - pkgrepo: ceph_repo_noarch

{% endif %}
