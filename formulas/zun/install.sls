uca:
  pkgrepo.managed:
    - humanname: Ubuntu Cloud Archive - Rocky
    - name: deb http://ubuntu-cloud.archive.canonical.com/ubuntu bionic-updates/rocky main
    - file: /etc/apt/sources.list.d/cloudarchive-rocky.list
    - keyid: ECD76E3E
    - keyserver: keyserver.ubuntu.com

docker_repo:
  pkgrepo.managed:
    - humanname: docker
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable
    - file: /etc/apt/sources.list.d/docker.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg


zun_packages:
  pkg.installed:
    - pkgs:
      - python-pip
      - git
      - python-openstackclient
      - python-memcache
      - etcd

pymysql_sa:
  pip.installed

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
    - branch: stable/rocky
    - target: /var/lib/zun
    - force_clone: true

pip install --upgrade -r /var/lib/zun/requirements.txt:
  cmd.run:
    - unless:
      - systemctl is-active zun-api

installzun:
  cmd.run:
    - name: python setup.py install
    - cwd : /var/lib/zun/
    - unless:
      - systemctl is-active zun-api
