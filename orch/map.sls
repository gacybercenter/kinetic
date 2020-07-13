# master_setup:
#   salt.state:
#     - tgt: 'salt'
#     - highstate: true
#
# pxe_setup:
#   salt.state:
#     - tgt: 'pxe'
#     - highstate: true


## nType is the endpoint type that the dependency is based on
## nState is the state that nType must have for the dependency to be satisfied
{% for type in pillar['hosts'] %}
  {% for nState, nDict in salt['pillar.get']('hosts:'+type+':needs', {}).items() if nState != {} %}
test_echo_{{ type }}_{{ nType }}_{{ nDict }}:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }} {{ nState }} {{ nDict }}
  {% endfor %}
{% endfor %}
