include:
  - formulas/openstack/common/repo
  - formulas/ceph/common/repo

{% if grains['os_family'] == 'Debian' %}

manila_packages:
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

{% elif grains['os_family'] == 'RedHat' %}

manila_packages:
  pkg.installed:
    - pkgs:
      - openstack-manila-share
      - python2-PyMySQL
      - python2-openstackclient
      - python2-manilaclient
      - python-memcached
      - centos-release-nfs-ganesha28
      - ceph-common
      - python-rbd
      - python-rados
    - reload_modules: true

ganesha_packages::
  pkg.installed:
    - pkgs:
      - nfs-ganesha
      - nfs-ganesha-ceph
    - require:
      - pkg: manila_packages

{% endif %}
