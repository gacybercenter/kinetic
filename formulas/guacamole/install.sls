## Copyright 2020 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

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

{% elif grains['os_family'] == 'RedHat' %}

CentOS-PowerTools:
  pkgrepo.managed:
    - humanname: CentOS-PowerTools
    - name: CentOS-PowerTools
    - mirrorlist: http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=PowerTools&infra=$infra
    - file: /etc/yum.repos.d/CentOS-PowerTools.repo
    - gpgkey: file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

guacamole_packages:
  pkg.installed:
    - pkgs:
      - epel-release
      - cairo-devel
      - libjpeg-turbo-devel
      - libpng-devel
      - libtool
      - uuid-devel
      - libvncserver-devel
      - freerdp-devel
      - ffmpeg-devel
      - pango-devel
      - libssh2-devel
      - libtelnet-devel
      - libwebsockets-devel
      - pulseaudio-libs-devel
      - openssl-devel
      - libvorbis-devel
      - libwebp-devel
      - tomcat

{% endif %}

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
