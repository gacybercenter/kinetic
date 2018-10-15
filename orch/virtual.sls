master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

{% for type in pillar['virtual'] %}
func:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - args:
      - echo {{ type }}
{% endfor %}
