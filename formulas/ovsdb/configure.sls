include:
  - formulas/ovsdb/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

ovn-northd-opts:
  file.managed:
    - name: /etc/sysconfig/ovn-northd
    - contents: |
        OVN_NORTHD_OPTS="--db-nb-addr=10.100.7.63 \
        --db-nb-create-insecure-remote=yes \
        --db-sb-addr={{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }} \
        --db-sb-create-insecure-remote=yes \
        --db-nb-cluster-local-addr={{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }} \
        --db-sb-cluster-local-addr={{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }} \
        {% if if grains['spawning'] != 0 %}
        --db-nb-cluster-remote-addr=
          {%- for host, addresses in salt['mine.get']('G@role:ovsdb and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
        {{ address }}
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %} \
        --db-sb-cluster-remote-addr=
          {%- for host, addresses in salt['mine.get']('G@role:ovsdb and G@spawning:0', 'network.ip_addrs', tgt_type='compound') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
        {{ address }}
              {%- endif -%}
            {%- endfor -%}
          {%- endfor %} \
        {% endif %}
        --ovn-northd-nb-db=
        {%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
          {%- for address in addresses -%}
            {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
        tcp:{{ address }}:6641
            {%- endif -%}
          {%- endfor -%}
          {% if loop.index < loop.length %},{% endif %}
        {%- endfor %} \
        --ovn-northd-sb-db=
        {%- for host, addresses in salt['mine.get']('role:ovsdb', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
          {%- for address in addresses -%}
            {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
        tcp:{{ address }}:6642
            {%- endif -%}
          {%- endfor -%}
          {% if loop.index < loop.length %},{% endif %}
        {%- endfor %}"

openvswitch_service:
  service.running:
{% if grains['os_family'] == 'RedHat' %}
    - name: openvswitch
{% elif grains['os_family'] == 'Debian' %}
    - name: openvswitch-switch
{% endif %}
    - enable: true

ovn_northd_service:
  service.running:
{% if grains['os_family'] == 'RedHat' %}
    - name: ovn-northd
{% elif grains['os_family'] == 'Debian' %}
    - name: ovn-central
{% endif %}
    - enable: true
    - require:
      - service: openvswitch_service
    - watch:
      - file: ovn-northd-opts

ovn-nbctl set-connection ptcp:6641:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service
    - unless:
      - ovn-nbctl get-connection | grep -q "ptcp:6641:0.0.0.0"

ovn-sbctl set-connection ptcp:6642:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service
    - unless:
      - ovn-sbctl get-connection | grep -q "ptcp:6642:0.0.0.0"

ovs-vsctl set open . external-ids:ovn-cms-options="enable-chassis-as-gw":
  cmd.run:
    - require:
      - service: ovn_northd_service
    - unless:
      - ovs-vsctl get open . external-ids:ovn-cms-options | grep -q "enable-chassis-as-gw"
