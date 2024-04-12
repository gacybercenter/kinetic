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

frr_repo:
  pkgrepo.managed:
    - humanname: frr-stable
    - name: deb https://deb.frrouting.org/frr {{ pillar['ubuntu']['name'] }} frr-stable
    - file: /etc/apt/sources.list.d/frr-stable.list
    - key_url: https://deb.frrouting.org/frr/keys.asc

update_packages_frr:
  pkg.uptodate:
    - refresh: true
    - onchanges:
      - frr_repo
    - dist_upgrade: True
