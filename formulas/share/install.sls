include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install
  - /formulas/common/openstack/repo
  - /formulas/common/ceph/repo

{% if grains['os_family'] == 'Debian' %}

share_packages:
  pkg.installed:
    - pkgs:
      - manila-share
      - python3-pymysql
      - python3-openstackclient
      - python3-manilaclient
      - python3-memcache
      - ceph-common
      - python3-rbd
      - python3-rados
      - nfs-ganesha
      - nfs-ganesha-ceph
      - python3-cephfs
      - sqlite3

{% elif grains['os_family'] == 'RedHat' %}

share_packages:
  pkg.installed:
    - pkgs:
      - openstack-manila-share
      - python3-PyMySQL
      - python3-openstackclient
      - python3-manilaclient
      - python3-memcached
      - centos-release-nfs-ganesha30
      - ceph-common
      - python3-rbd
      - python3-rados
    - reload_modules: true

ganesha_packages:
  pkg.installed:
    - pkgs:
      - nfs-ganesha
      - nfs-ganesha-ceph
      - nfs-ganesha-selinux
      - nfs-ganesha-rados-urls
      - nfs-ganesha-rados-grace
    - require:
      - pkg: share_packages

{% endif %}
