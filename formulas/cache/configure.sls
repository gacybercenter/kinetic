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

/var/cache/apt-cacher-ng:
  file.directory

/root/acng.conf:
  file.managed:
    - source: salt://formulas/cache/files/acng.conf

curl https://www.centos.org/download/full-mirrorlist.csv | sed 's/^.*"http:/http:/' | sed 's/".*$//' | grep ^http >/root/centos_mirrors:
  cmd.run:
    - creates: /root/centos_mirrors

/root/acng.dockerfile:
  file.managed:
    - source: salt://formulas/cache/files/acng.dockerfile

buildah bud -t acng acng.dockerfile:
  cmd.run:
    - onchanges:
      - file: /root/acng.dockerfile

podman create -d -p 3142:3142 --name apt-cacher-ng --volume apt-cacher-ng:/var/cache/apt-cacher-ng acng:
  cmd.run:
    - unless:
      - podman container ls -a | grep -q apt-cacher-ng

/etc/systemd/system/apt-cacher-ng-container.service:
  file.managed:
    - source: salt://formulas/cache/files/apt-cacher-ng-container.service
    - require:
      - cmd: podman create -d -p 3142:3142 --name apt-cacher-ng --volume apt-cacher-ng:/var/cache/apt-cacher-ng acng

apt-cacher-ng-container:
  service.running:
    - enable: True
    - watch:
      - file: /etc/systemd/system/apt-cacher-ng-container.service
