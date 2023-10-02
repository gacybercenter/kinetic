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
  # - /formulas/common/docker/repo

{% if grains['os_family'] == 'Debian' %}

guacamole_packages:
  pkg.installed:
    - pkgs:
      - docker.io
      - docker-compose
      - containerd
      - python3-pip
      - default-libmysqlclient-dev
      - pkg-config

guacamole_pip:
  pip.installed:
    - bin_env: '/usr/bin/pip3'
    - reload_modules: True
    - pkgs:
      - mysql-connector-python
      - mysqlclient
      - docker-compose == 1.9.0
      - docker == 5.0.3
    - requires:
      - pkg: guacamole_packages

salt-pip_installs:
  pip.installed:
    - bin_env: '/usr/bin/salt-pip'
    - reload_modules: true
    - pkgs:
      - mysql-connector-python
      - mysqlclient
      - docker-compose == 1.9.0
      - docker == 5.0.3
    - requires:
      - pkg: guacamole_packages
      - pip: guacamole_pip

{% elif grains['os_family'] == 'RedHat' %}

# CentOS-PowerTools:
#   pkgrepo.managed:
#     - humanname: CentOS-PowerTools
#     - name: CentOS-PowerTools
#     - mirrorlist: http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=PowerTools&infra=$infra
#     - file: /etc/yum.repos.d/CentOS-PowerTools.repo
#     - gpgkey: file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

# guacamole_packages:
#   pkg.installed:
#     - pkgs:
#       - epel-release
#       - cairo-devel
#       - libjpeg-turbo-devel
#       - libjpeg-devel
#       - libpng-devel
#       - libtool
#       - uuid-devel
#       - freerdp-devel
#       - ffmpeg-devel
#       - pango-devel
#       - libssh2-devel
#       - libtelnet-devel
#       - libvncserver-devel
#       - libwebsockets-devel
#       - pulseaudio-libs-devel
#       - openssl-devel
#       - libvorbis-devel
#       - libwebp-devel
#       - tomcat

{% endif %}

/opt/guacamole/docker-compose.yml:
  file.managed:
    - source: salt://formulas/guacamole/files/docker-compose.yml
    - makedirs: True
    - template: jinja
    - defaults:
        guacadmin_password: {{ pillar['guacamole']['guacadmin_password'] }}
        guacamole_mysql_password: {{ pillar['guacamole']['guacamole_mysql_password'] }}
        guacamole_mysql_host: {{ pillar['haproxy']['guacamole_domain'] }}
        guacamole_db: {{ pillar['integrated_services']["guacamole"]['configuration']['dbs'][0] }}

/opt/guacamole/init/initdb.sql:
  file.managed:
    - source: salt://formulas/guacamole/files/initdb.sql
    - makedirs: True

guacamole_redirect:
  file.managed:
    - makedirs: True
    - names:
      - /home/guacamole/tomcat/webapps/ROOT/index.jsp:
        - source: salt://formulas/guacamole/files/index.jsp
      - /home/guacamole/tomcat/webapps/ROOT/WEB-INF/web.xml:
        - source: salt://formulas/guacamole/files/web.xml

# NOTE(chateaulav): current reference for branding:
#                   https://github.com/Zer0CoolX/guacamole-customize-loginscreen-extension
guacamole_extensions:
  file.managed:
    - makedirs: True
    - names:
      - /opt/guacamole/guacamole/extensions/guacamole-auth-quickconnect-1.5.0.jar:
        - source: salt://formulas/guacamole/files/guacamole-auth-quickconnect-1.5.0.jar
      - /opt/guacamole/guacamole/extensions/guacamole-history-recording-storage-1.5.0.jar:
        - source: salt://formulas/guacamole/files/guacamole-history-recording-storage-1.5.0.jar
      - /opt/guacamole/guacamole/extensions/branding.jar:
        - source: salt://formulas/guacamole/files/branding.jar