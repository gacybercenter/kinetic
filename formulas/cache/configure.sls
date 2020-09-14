include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}
spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - name: mine.send
    - m_name: spawnzero_complete
    - kwargs:
        mine_function: grains.item
    - args:
      - spawnzero_complete
    - onchanges:
      - grains: spawnzero_complete

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

apt-cacher-ng-conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt-cacher-ng/acng.conf
{% elif grains['os_family'] == 'RedHat' %}
    - name: /root/acng.conf
{% endif %}
    - source: salt://formulas/cache/files/acng.conf

security-conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt-cacher-ng/security.conf
{% elif grains['os_family'] == 'RedHat' %}
    - name: /root/security.conf
{% endif %}
    - contents: |
        AdminAuth: acng:{{ pillar['cache']['maintenance_password'] }}

get_centos_mirros:
  cmd.run:
{% if grains['os_family'] == 'Debian' %}
    - name: curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/etc/apt-cacher-ng/centos_mirrors
    - creates: /etc/apt-cacher-ng/centos_mirrors
{% elif grains['os_family'] == 'RedHat' %}
    - name: curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/root/centos_mirrors
    - creates: /root/centos_mirrors
{% endif %}

{% if (salt['grains.get']('selinux:enabled', False) == True) and (salt['grains.get']('selinux:enforced', 'Permissive') == 'Enforcing')  %}
container_manage_cgroup:
  selinux.boolean:
    - value: 1
    - persist: True
{% endif %}

{% if grains['os_family'] == 'Debian' %}

apt-cacher-ng_service:
  service.running:
    - name: apt-cacher-ng
    - enable: True
    - watch:
      - file: apt-cacher-ng-conf
      - file: security-conf
      - cmd: get_centos_mirros

{% elif grains['os_family'] == 'RedHat' %}

/root/acng.dockerfile:
  file.managed:
    - source: salt://formulas/cache/files/acng.dockerfile

build acng container image:
  cmd.run:
    - name: buildah bud -t acng acng.dockerfile
    - onchanges:
      - file: /root/acng.dockerfile
      - file: /root/acng.conf
      - file: /root/security.conf

## working around https://github.com/containers/libpod/issues/4605 by temporarily removing volumes
## podman create -d -p 3142:3142 --name apt-cacher-ng --volume apt-cacher-ng:/var/cache/apt-cacher-ng acng
create acng container:
  cmd.run:
    - name: podman create -d -p 3142:3142 --name apt-cacher-ng acng
    - require:
      - cmd: build acng container image
    - unless:
      - podman container ls -a | grep -q apt-cacher-ng

/etc/systemd/system/apt-cacher-ng-container.service:
  file.managed:
    - source: salt://formulas/cache/files/apt-cacher-ng-container.service
    - mode: 644
    - require:
      - cmd: create acng container

apt-cacher-ng-container:
  service.running:
    - enable: True
    - require:
      - file: /etc/systemd/system/apt-cacher-ng-container.service
    - watch:
      - file: /etc/systemd/system/apt-cacher-ng-container.service

{% endif %}
