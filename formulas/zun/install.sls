
include:
  - formulas/openstack/common/repo
  - formulas/ceph/common/repo
  - formulas/docker/common/repo
  
{% if grains['os_family'] == 'Debian' %}

swift_packages:
  pkg.installed:
    - pkgs:
      - radosgw
      - python3-openstackclient

{% elif grains['os_family'] == 'RedHat' %}

swift_packages:
  pkg.installed:
    - pkgs:
      - ceph-radosgw
      - python2-openstackclient

{% endif %}



uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - train
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu bionic-updates/train main
    - file: /etc/apt/sources.list.d/cloudarchive-train.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

docker_repo:
  pkgrepo.managed:
    - humanname: docker
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable
    - file: /etc/apt/sources.list.d/docker.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg

update_packages_uca:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: uca
      - pkgrepo: docker_repo
    - dist_upgrade: True

zun_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - python3-memcache
      - etcd
      - numactl
      - python3-pymysql

pymysql_sa:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

zun:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/zun
    - system: True
    - groups:
      - zun

/etc/zun:
  file.directory:
    - user: zun
    - group: zun
    - mode: 755
    - makedirs: True

/etc/zun/rootwrap.d:
  file.directory:
    - user: root
    - group: root
    - makedirs: True

zun_latest:
  git.latest:
    - name: https://git.openstack.org/openstack/zun.git
    - branch: stable/train
    - target: /var/lib/zun
    - force_clone: true

pip3 install --upgrade -r /var/lib/zun/requirements.txt:
  cmd.run:
    - unless:
      - systemctl is-active zun-api

installzun:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/zun/
    - unless:
      - systemctl is-active zun-api
