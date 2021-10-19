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
  - /formulas/common/docker/repo

{% if grains['os_family'] == 'Debian' %}

guacamole_packages:
  pkg.installed:
    - pkgs:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose

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