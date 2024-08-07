nftables:
  pkg.installed:
    - name: firewalld

nftables_service:
  service.running:
    - name: firewalld
    - enable: true
    - require:
      - pkg: nftables

common_remove:
  pkg.removed:
    - pkgs:
      - nftables

openstack_api:
  firewalld.service:
    - name: openstack_api
    - ports: [53/tcp,{{ pillar['cache']['lancache']['http_port'] }}/tcp,443/tcp,9292/tcp,7480/tcp,5000/tcp,8774/tcp,8778/tcp,8776/tcp,9696/tcp,8004/tcp,8000/tcp,9001/tcp,9517/tcp,{{ pillar['cache']['nexusproxy']['port'] }}/tcp]

#openstack_api:
#  nftables.append:
#    - position: 1
#    - table: filter
#    - family: inet
#    - chain: input
#    - jump: accept
#    - match: state
#    - connstate: new
#    - dports: 53,{{ pillar['cache']['lancache']['http_port'] }},443,9292,7480,5000,8774,8778,8776,9696,8004,8000,9001,9517,{{ pillar['cache']['nexusproxy']['port'] }}
#    - proto: tcp
#    - source: '{{ pillar['networking']['subnets']['public'] }}'
#    - save: True
#    - unless:
#      - nft list table inet filter | grep -q '{{ pillar['networking']['subnets']['public'] }} tcp dport'

#public_block:
#  nftables.append:
#    - position: 2
#    - table: filter
#    - family: inet
#    - chain: input
#    - jump: drop
#    - match: state
#    - connstate: new
#    - source: '{{ pillar['networking']['subnets']['public'] }}'
#    - save: True
#    - unless:
#      - nft list table inet filter | grep -q '{{ pillar['networking']['subnets']['public'] }} drop'
