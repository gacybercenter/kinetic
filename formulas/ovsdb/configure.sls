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
