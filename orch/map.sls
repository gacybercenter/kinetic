master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

pxe_setup:
  salt.state:
    - tgt: 'pxe'
    - highstate: true

{% for type in pillar['hosts'] %}
  {% for need in pillar['hosts'][type]['needs'] %}
test_echo_{{ need }}:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }} {{ need }}
  {% endfor %}
{% endfor %}
