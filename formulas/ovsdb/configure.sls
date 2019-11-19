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
    - name: openvswitch
    - enable: true

ovn_northd_service:
  service.running:
    - name: ovn-northd
    - enable: true
    - require:
      - service: openvswitch_service

ovn-nbctl set-connection ptcp:6641:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service

ovn-sbctl set-connection ptcp:6642:0.0.0.0 -- set connection . inactivity_probe=60000:
  cmd.run:
    - require:
      - service: ovn_northd_service

ovs-vsctl set open . external-ids:ovn-cms-options="enable-chassis-as-gw":
  cmd.run:
    - require:
      - service: ovn_northd_service
