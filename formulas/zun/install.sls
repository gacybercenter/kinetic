
include:
  - formulas/openstack/common/repo
  - formulas/ceph/common/repo
  - formulas/docker/common/repo

{% if grains['os_family'] == 'Debian' %}

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

{% elif grains['os_family'] == 'RedHat' %}

zun_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-devel
      - libffi-devel
      - gcc
      - openssl-devel
      - etcd
      - numactl
      - python36-PyMySQL

python3-memcached:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

python-openstackclient:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

{% endif %}

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

zun_requirements:
  cmd.run:
    - name: pip3 install --upgrade -r /var/lib/zun/requirements.txt
    - unless:
      - systemctl is-active zun-api
    - require:
      - git: zun_latest

installzun:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/zun/
    - unless:
      - systemctl is-active zun-api
    - require:
      - cmd: zun_requirements
