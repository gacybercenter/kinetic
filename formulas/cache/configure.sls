include:
  - /formulas/cache/install
  - /formulas/common/base
  - /formulas/common/networking

{% if grains['spawning'] == 0 %}
spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."
{% endif %}

apt-cacher-ng-conf:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/apt-cacher-ng/acng.conf
{% elif grains['os_family'] == 'RedHat' %}
    - name: /root/acng.conf
{% endif %}
    - source: salt://formulas/cache/files/acng.conf

get_centos_mirros:
  cmd.run:
{% if grains['os_family'] == 'Debian' %}
    - name: curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/etc/apt-cacher-ng/centos_mirrors
    - creates: /etc/apt-cacher-ng/centos_mirrors
{% elif grains['os_family'] == 'RedHat' %}
    - name: curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/root/centos_mirrors
    - creates: /root/centos_mirrors
{% endif %}

{% if grains['os_family'] == 'Debian' %}

apt-cacher-ng_service:
  service.running:
    - name: apt-cacher-ng
    - enable: True
    - watch:
      - file: apt-cacher-ng-conf
      - cmd: get_centos_mirros

{% elif grains['os_family'] == 'RedHat' %}

/root/acng.dockerfile:
  file.managed:
    - source: salt://formulas/cache/files/acng.dockerfile

container_manage_cgroup:
  selinux.boolean:
    - value: 1
    - persist: True

build acng container image:
  cmd.run:
    - name: buildah bud -t acng acng.dockerfile
    - onchanges:
      - file: /root/acng.dockerfile
      - file: /root/acng.conf

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
