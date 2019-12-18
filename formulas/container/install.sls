include:
  - formulas/openstack/common/repo
  - formulas/docker/common/repo

{% if grains['os_family'] == 'Debian' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
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
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

  {% elif pillar['neutron']['backend'] == "networking-ovn" %}

container_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-openstackclient
      - docker-ce
      - ovn-host
      - python3-tornado
      - python3-pymysql

pymysql_sa:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

    {% endif %}

{% elif grains['os_family'] == 'RedHat' %}
  {% if pillar['neutron']['backend'] == "linuxbridge" %}
container_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-devel
      - libffi-devel
      - gcc
      - openssl-devel
      - openstack-neutron-linuxbridge
      - python36-PyMySQL
      - docker-ce
      - numactl
  {% elif pillar['neutron']['backend'] == "networking-ovn" %}
container_packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - git
      - python3-devel
      - libffi-devel
      - gcc
      - openssl-devel
      - ovn-host
      - python36-PyMySQL
      - docker-ce
      - libibverbs
      - numactl
  {% endif %}

python-openstackclient:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: true

{% endif %}

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

kuryr_requirements:
  cmd.run:
    - name: pip3 install -r /var/lib/kuryr/requirements.txt
    - unless:
      - systemctl is-active kuryr-libnetwork
    - require:
      - git: kuryr_latest

installkuryr:
  cmd.run:
    - name: python3 setup.py install
    - cwd: /var/lib/kuryr/
    - unless:
      - systemctl is-active kuryr-libnetwork
    - require:
      - cmd: kuryr_requirements

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
      - systemctl is-active zun-compute
    - require:
      - git: zun_latest

installzun:
  cmd.run:
    - name: python3 setup.py install
    - cwd : /var/lib/zun/
    - unless:
      - systemctl is-active zun-compute
    - require:
      - cmd: zun_requirements
