## Copyright 2019 Augusta University
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

update_ceph_conf_{{ data['id'] }}:
  local.state.apply:
    - tgt_type: compound
    - tgt: 'E@(cephmon*|volume*|compute*|glance*|storage*|swift*|mds*|share*) and G@build_phase:configure'
    - args:
      - mods: formulas/common/ceph/configure
