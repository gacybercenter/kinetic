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


container_packages:
  pkg.installed:
    - pkgs:
      - python-pip
      - git
      - python-openstackclient
      - docker-ce

pymysql_sa:
  pip.installed

kuryr:
  group.present:
    - system: True
  user.present:
    - shell: /bin/false
    - createhome: True
    - home: /var/lib/kuryr
    - system: True
    - groups:
      - kuryr

/etc/kuryr:
  file.directory:
    - user: kuryr
    - group: kuryr
    - mode: 755
    - makedirs: True

kuryr_latest:
  git.latest:
    - name: https://git.openstack.org/openstack/kuryr-libnetwork.git
    - branch: stable/rocky
    - target: /var/lib/kuryr
    - fetch_tags: True
    - rev: 2.0.0
    - force_clone: true

pip install -r /var/lib/kuryr/requirements.txt:
  cmd.run

installkuryr:
  cmd.run:
    - name: python setup.py install
    - cwd: /var/lib/kuryr/

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
    - fetch_tags: True
    - rev: 2.1.0
    - force_clone: true

pip install -r /var/lib/zun/requirements.txt:
  cmd.run

installzun:
  cmd.run:
    - name: python setup.py install
    - cwd : /var/lib/zun/
