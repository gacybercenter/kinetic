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

{% if grains['os_family'] == 'Debian' %}

frr_repo:
  pkgrepo.managed:
    - humanname: frr-stable
    - name: deb https://deb.frrouting.org/frr focal frr-stable
    - file: /etc/apt/sources.list.d/frr-stable.list
    - key_url: https://deb.frrouting.org/frr/keys.asc

update_packages_frr:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - frr_repo
    - dist_upgrade: True

{% elif grains['os_family'] == 'RedHat' %}

frr_repo:
  pkgrepo.managed:
    - name: frr
    - baseurl: https://rpm.frrouting.org/repo/el8/frr
    - file: /etc/yum.repos.d/frr.repo
    - gpgkey: https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x7ab8ac624cba356cb6216d48f66b5a9140673a87

frr_extras_repo:
  pkgrepo.managed:
    - name: frr_extras
    - baseurl: https://rpm.frrouting.org/repo/el8/extras
    - file: /etc/yum.repos.d/frr_extas.repo
    - gpgkey: https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x7ab8ac624cba356cb6216d48f66b5a9140673a87

update_packages_frr:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - pkgrepo: frr_repo
      - pkgrepo: frr_extras_repo

{% endif %}
