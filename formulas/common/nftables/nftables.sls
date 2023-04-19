nftables:
  pkg.installed

nftables_service:
  service.running:
    - name: nftables
    - enable: true
    - require:
      - pkg: nftables

common_remove:
  pkg.removed:
    - pkgs:
      - firewalld

{% if grains['build_phase'] != 'configure' %}
openstack_api:
  nftables.append:
    - position: 1
    - table: filter
    - family: inet
    - chain: input
    - jump: accept
    - match: state
    - connstate: new
    - dports: 443,80,9292,7480,5000,8774,8778,8776,9696,8004,8000,9001,9517,3142
    - proto: tcp
    - source: '10.101.0.0/16'
    - save: True

public_block_22:
  nftables.append:
    - position: 2
    - table: filter
    - family: inet
    - chain: input
    - jump: drop
    - match: state
    - connstate: new
    - source: '10.101.20.0/22'
    - save: True

public_block_21:
  nftables.append:
    - position: 3
    - table: filter
    - family: inet
    - chain: input
    - jump: drop
    - match: state
    - connstate: new
    - source: '10.101.24.0/21'
    - save: True

public_block_19:
  nftables.append:
    - position: 4
    - table: filter
    - family: inet
    - chain: input
    - jump: drop
    - match: state
    - connstate: new
    - source: '10.101.32.0/19'
    - save: True

public_block_18:
  nftables.append:
    - position: 5
    - table: filter
    - family: inet
    - chain: input
    - jump: drop
    - match: state
    - connstate: new
    - source: '10.101.64.0/18'
    - save: True

public_block_17:
  nftables.append:
    - position: 6
    - table: filter
    - family: inet
    - chain: input
    - jump: drop
    - match: state
    - connstate: new
    - source: '10.101.128.0/17'
    - save: True
{% endif %}