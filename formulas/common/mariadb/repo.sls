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

mariadb_repo:
  pkgrepo.managed:
    - humanname: mariadb10.10
    - name: deb http://downloads.mariadb.com/MariaDB/mariadb-10.10/repo/ubuntu {{ pillar['ubuntu']['name'] }} main
    - file: /etc/apt/sources.list.d/mariadb.list
    - keyid: F1656F24C74CD1D8
    - keyserver: keyserver.ubuntu.com

#mariadb_maxscale_repo:
#  pkgrepo.managed:
#    - humanname: mariadb_maxscale
#    - name: deb http://downloads.mariadb.com/MaxScale/2.4/ubuntu {{ pillar['ubuntu']['name'] }} main
#    - file: /etc/apt/sources.list.d/mariadb_maxscale.list
#    - keyid: 135659E928C12247
#    - keyserver: keyserver.ubuntu.com

mariadb_tools_repo:
  pkgrepo.managed:
    - humanname: mariadb_tools
    - name: deb http://downloads.mariadb.com/Tools/ubuntu {{ pillar['ubuntu']['name'] }} main
    - file: /etc/apt/sources.list.d/mariadb_tools.list
    - keyid: CE1A3DD5E3C94F49
    - keyserver: keyserver.ubuntu.com

update_packages_mariadb:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - mariadb_tools_repo
#      - mariadb_maxscale_repo
      - mariadb_repo
    - dist_upgrade: True
