# master_setup:
#   salt.state:
#     - tgt: 'salt'
#     - highstate: true
#
# pxe_setup:
#   salt.state:
#     - tgt: 'pxe'
#     - highstate: true

{% for type in pillar['hosts'] %}
  {% for nType, state in salt['pillar.get']('hosts:'+type+':needs', {}).items() if nType != {} %}
test_echo_{{ type }}_{{ nType }}_{{ state }}:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }} {{ nType }} {{ state }}
  {% endfor %}
{% endfor %}
