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

/root/acng.conf:
  file.managed:
    - source: salt://formulas/cache/files/acng.conf

curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/root/centos_mirrors:
  cmd.run:
    - creates: /root/centos_mirrors

/root/Dockerfile:
  file.managed:
    - source: salt://formulas/cache/files/acng.dockerfile

{% if grains['os_family'] == 'RedHat' %}

container_manage_cgroup:
  selinux.boolean:
    - value: 1
    - persist: True

{% endif %}

{% if grains['os_family'] == 'RedHat' %}
  {% set build_cmd = 'buildah bud' %}
  {% set docker_bin = 'podman' %}
{% elif grains['os_family'] == 'Debian' %}
  {% set build_cmd = 'docker build' %}
  {% set docker_bin = 'docker' %}
{% endif %}

build acng container image:
  cmd.run:
    - name: {{ build_cmd }} -t acng .
    - onchanges:
      - file: /root/Dockerfile
      - file: /root/acng.conf

## working around https://github.com/containers/libpod/issues/4605 by temporarily removing volumes
## podman create -d -p 3142:3142 --name apt-cacher-ng --volume apt-cacher-ng:/var/cache/apt-cacher-ng acng
create acng container:
  cmd.run:
    - name: {{ docker_bin }} create -d -p 3142:3142 --name apt-cacher-ng acng
    - require:
      - cmd: build acng container image
    - unless:
      - {{ docker_bin }} container ls -a | grep -q apt-cacher-ng

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
