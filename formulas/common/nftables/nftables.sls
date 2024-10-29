nftables:
  pkg.installed:
    - name: nftables
    - name: nftables

nftables_service:
  service.running:
    - name: nftables
    - name: nftables
    - enable: true
    - require:
      - pkg: nftables

common_remove:
  pkg.removed:
    - pkgs:
      - firewalld

nft_init:
  cmd.run:
    - name: nft -f /etc/nftables.conf
    - unless:
      - nft list table inet filter |grep inet

openstack_api_cmd:
  cmd.run: 
    - name: nft add rule inet filter input ct state { new } ip saddr 10.201.0.0/16 tcp dport { 53,{{ pillar['cache']['lancache']['http_port'] }},443,9292,7480,5000,8774,8778,8776,9696,8004,8000,9001,9517,{{ pillar['cache']['nexusproxy']['port'] }} } accept
    - unless:
      - nft list table inet filter | grep -q '{{ pillar['networking']['subnets']['public'] }} tcp dport'

public_block:
  nftables.append:
    - position: 2
    - table: filter
    - family: inet
    - chain: input
    - jump: drop
    - match: state
    - connstate: new
    - source: '{{ pillar['networking']['subnets']['public'] }}'
    - save: True
    - unless:
      - nft list table inet filter | grep -q '{{ pillar['networking']['subnets']['public'] }} drop'