nftables:
  pkg.installed:
    - name: nftables

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

nft_ipv4_table:
  nftables.table_present:
    - name: filter
    - family: inet
nft_ipv4_input_chain:
  nftables.chain_present:
    - name: input
    - table: filter
    - family: inet

openstack_api:
  nftables.append:
    - position: 1
    - table: filter
#    - family: inet
    - chain: input
    - jump: accept
    - match: state
    - connstate: new
    - dports: 53,{{ pillar['cache']['lancache']['http_port'] }},443,9292,7480,5000,8774,8778,8776,9696,8004,8000,9001,9517,{{ pillar['cache']['nexusproxy']['port'] }}
    - proto: tcp
    - source: '{{ pillar['networking']['subnets']['public'] }}'
    - save: True
    - unless:
      - nft list table inet filter | grep -q '{{ pillar['networking']['subnets']['public'] }} tcp dport'

public_block:
  nftables.append:
    - position: 2
    - table: filter
#    - family: inet
    - chain: input
    - jump: drop
    - match: state
    - connstate: new
    - source: '{{ pillar['networking']['subnets']['public'] }}'
    - save: True
    - unless:
      - nft list table inet filter | grep -q '{{ pillar['networking']['subnets']['public'] }} drop'