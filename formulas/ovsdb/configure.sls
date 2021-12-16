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

include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

{% if neutron_backend == 'networking-ovn' %}
ovn_northd_opts:
  file.managed:
      {% if grains['os_family'] == "RedHat" %}
    - name: /etc/sysconfig/ovn-northd
      {% elif grains['os_family'] == "Debian" %}
    - name: /etc/default/ovn-central
      {% endif %}
    - source: salt://formulas/ovsdb/files/ovn-northd
    - template: jinja
    - defaults:
        {% if grains['os_family'] == "RedHat" %}
        opts_name: OVN_NORTHD_OPTS
        {% elif grains['os_family'] == "Debian" %}
        opts_name: OVN_CTL_OPTS
        {% endif %}
        self_ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
        nb_cluster: {{ constructor.ovn_nb_connection_constructor() }}
        sb_cluster: {{ constructor.ovn_sb_connection_constructor() }}
        {% if grains['spawning'] != 0 %}
        cluster_remote: |-
            --db-nb-cluster-remote-addr={{ constructor.ovn_cluster_remote_constructor() }} \
            --db-sb-cluster-remote-addr={{ constructor.ovn_cluster_remote_constructor() }}
        {% elif grains['spawning'] == 0 %}
        cluster_remote: ""
        {% endif %}

ovn_northd_service:
  service.running:
{% if grains['os_family'] == 'RedHat' %}
    - name: ovn-northd
{% elif grains['os_family'] == 'Debian' %}
    - name: ovn-central
{% endif %}
    - enable: true
    - watch:
      - file: ovn_northd_opts

openvswitch_service:
  service.running:
{% if grains['os_family'] == 'RedHat' %}
    - name: openvswitch
{% elif grains['os_family'] == 'Debian' %}
    - name: openvswitch-switch
{% endif %}
    - enable: true
    - require:
      - service: ovn_northd_service

ovn-nbctl --no-leader-only set-connection ptcp:6641:0.0.0.0 -- set connection . inactivity_probe=180000:
  cmd.run:
    - require:
      - service: ovn_northd_service
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - unless:
      - ovn-nbctl --no-leader-only get-connection | grep -q "ptcp:6641:0.0.0.0"

ovn-sbctl --no-leader-only set-connection ptcp:6642:0.0.0.0 -- set connection . inactivity_probe=180000:
  cmd.run:
    - require:
      - service: ovn_northd_service
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - unless:
      - ovn-sbctl --no-leader-only get-connection | grep -q "ptcp:6642:0.0.0.0"

ovs-vsctl set open . external-ids:ovn-cms-options="enable-chassis-as-gw":
  cmd.run:
    - require:
      - service: ovn_northd_service
      - service: openvswitch_service
    - retry:
        attempts: 3
        interval: 10
        splay: 5
    - unless:
      - ovs-vsctl get open . external-ids:ovn-cms-options | grep -q "enable-chassis-as-gw"

## This is gross.  Should write an ovs-appctl module to handle things like this
## Note that extra quotes are required around the state alterations because of ':'
## yaml parsing weirdness
set_southbound_election_timer_final:
  cmd.run:
    - name: >
        ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/change-election-timer OVN_Southbound 2000 &&
        ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/change-election-timer OVN_Southbound 4000 &&
        ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/change-election-timer OVN_Southbound 5000
    - unless:
      - 'ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep -q "Election timer: 5000"'
    - onlyif:
      - 'ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep -q "Role: leader"'
{% else %}
ovn_use:
  event.send:
    - name: networking-ovn
    - data:
        config_error: "You are spinnning osvdb nodes, but did not set networking-ovn as the backend. Spin up network nodes instead or change the answer file to networking-ovn."
