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
{% set chains == ["input", "output", "forward"] %}
{% for chain  in chains %}
nft_ipv4_{{ chain }}_chain:
  nftables.chain_present:
    - name: {{ chain }}
    - table: filter
nft_ipv4_{{ chain }}_policy:
  nftables.set_policy:
    - name: {{ chain }}
    - table: filter
    - policy: accept
{% endfor %}

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
      - nft list table ip filter | grep -q '{{ pillar['networking']['subnets']['public'] }} tcp dport'

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
      - nft list table ip filter | grep -q '{{ pillar['networking']['subnets']['public'] }} drop'