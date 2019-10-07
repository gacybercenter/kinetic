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

container_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - docker-ce
      - neutron-linuxbridge-agent
      - python3-tornado
      - python3-pymysql

pymysql_sa:
  pip.installed:
    - bin_env: '/bin/pip3'
    - reload_modules: true

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
    - branch: stable/train
    - target: /var/lib/kuryr
    - force_clone: true

pip3 install -r /var/lib/kuryr/requirements.txt:
  cmd.run:
    - unless:
      - systemctl is-active kuryr-libnetwork

installkuryr:
  cmd.run:
    - name: python3 setup.py install
    - cwd: /var/lib/kuryr/
    - unless:
      - systemctl is-active kuryr-libnetwork

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

pip3 install -r /var/lib/zun/requirements.txt:
  cmd.run:
    - unless:
      - systemctl is-active zun-compute

installzun:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/zun/
    - unless:
      - systemctl is-active zun-compute
