include:
  - /formulas/common/base
  - /formulas/common/networking
  - /formulas/common/install

{% if grains['os_family'] == 'Debian' %}

guacamole_packages:
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
      - tomcat9

guacamole-server:
  archive.extracted:
    - name: /root/guacamole-server
    - source: https://downloads.apache.org/guacamole/1.2.0/source/guacamole-server-1.2.0.tar.gz
    - source_hash: https://www.apache.org/dist/guacamole/1.2.0/source/guacamole-server-1.2.0.tar.gz.sha256

install_guacamole_server:
  cmd.run:
    - name: ./configure --with-systemd-dir=/etc/systemd/system && make && make install && ldconfig
    - cwd: /root/guacamole-server/guacamole-server-1.2.0/
    - creates:
      - /usr/local/sbin/guacd

download_guacamole_client:
  file.managed:
    - name: /var/lib/tomcat9/webapps/guacamole.war
    - source: https://downloads.apache.org/guacamole/1.2.0/binary/guacamole-1.2.0.war
    - source_hash: https://downloads.apache.org/guacamole/1.2.0/binary/guacamole-1.2.0.war.sha256

/etc/guacamole/extensions:
  file.directory:
    - makedirs: True

guacamole-quickconnect:
  archive.extracted:
    - name: /root/guacamole-quickconnect
    - source: https://downloads.apache.org/guacamole/1.2.0/binary/guacamole-auth-quickconnect-1.2.0.tar.gz
    - source_hash: https://www.apache.org/dist/guacamole/1.2.0/binary/guacamole-auth-quickconnect-1.2.0.tar.gz.sha256

install-quickconnect-extension:
  file.copy:
    - name: /etc/guacamole/extensions/guacamole-auth-quickconnect-1.2.0.jar
    - source: /root/guacamole-quickconnect/guacamole-auth-quickconnect-1.2.0/guacamole-auth-quickconnect-1.2.0.jar

{% elif grains['os_family'] == 'RedHat' %}

guacamole_packages:
  pkg.installed:
    - sources:
      - teleport: https://get.gravitational.com/teleport-4.3.5-1.x86_64.rpm

{% endif %}
