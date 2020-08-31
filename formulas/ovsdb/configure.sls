include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - name: mine.send
    - m_name: spawnzero_complete
    - kwargs:
        mine_function: grains.item
    - args:
      - spawnzero_complete
    - onchanges:
      - grains: spawnzero_complete

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

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
        nb_cluster: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          tcp:{{ address }}:6641
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        sb_cluster: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          tcp:{{ address }}:6642
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
          {% if grains['spawning'] != 0 %}
        cluster_remote: |-
          --db-nb-cluster-remote-addr=
          {%- for host, addresses in salt['mine.get']('G@role:ovsdb and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %} \
          --db-sb-cluster-remote-addr=
          {%- for host, addresses in salt['mine.get']('G@role:ovsdb and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          {{ address }}
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
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

### This is gross.  Should write an ovs-appctl module to handle things like this
# set_election_timer_p1:
#   cmd.run:
#     - name: ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/change-election-timer OVN_Southbound 2000
#     - prereq:
#       - cmd: set_election_timer_p2
#     - onlyif:
#       - ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep -q "Role: leader"
#
# set_election_timer_p2:
#   cmd.run:
#     - name: ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/change-election-timer OVN_Southbound 4000
#     - prereq:
#       - cmd: set_election_timer_final
#     - onlyif:
#       - ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep -q "Role: leader"

set_election_timer_final:
  cmd.run:
    - name: ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/change-election-timer OVN_Southbound 5000
    - unless:
      - ovs-appctl -t /run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep -q "Election timer: 5000"
