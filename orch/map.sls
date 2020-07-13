master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

pxe_setup:
  salt.state:
    - tgt: 'pxe'
    - highstate: true

{% for type in pillar['hosts'] %}
test_echo_{{ type }}:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }}
{% endfor %}
