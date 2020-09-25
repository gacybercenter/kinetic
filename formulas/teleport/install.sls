include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

{% if grains['os_family'] == 'Debian' %}

teleport_packages:
  pkg.installed:
    - pkgs:
      - libcairo2-dev
      - libjpeg-turbo8-dev
      - libpng-dev
      - libtool-bin
      - libossp-uuid-dev
      - libvncclient1
      - freerdp2-dev
      - freerdp2-wayland
      - libavcodec-dev
      - libavformat-dev
      - libavutil-dev
      - libswscale-dev
      - libpango1.0-dev
      - libssh2-1-dev
      - libtelnet-dev
      - libvncserver-dev
      - libwebsockets-dev
      - libpulse-dev
      - libssl-dev
      - libvorbis-dev
      - libwebp-dev

guacamole-server:
  archive.extracted:
    - name: /root/guacamole-server
    - source: https://mirrors.sonic.net/apache/guacamole/1.2.0/source/guacamole-server-1.2.0.tar.gz

{% elif grains['os_family'] == 'RedHat' %}

teleport_packages:
  pkg.installed:
    - sources:
      - teleport: https://get.gravitational.com/teleport-4.3.5-1.x86_64.rpm

{% endif %}
