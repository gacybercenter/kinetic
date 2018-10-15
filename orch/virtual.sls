master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

{% for type in pillar['virtual'] %}
  {% for count in range(1, pillar['virtual'][type]['config']['count']) %}
    echo {{ count }}:
      salt.function:
        - name: cmd.ruin
        - tgt: salt
        - args
          - echo {{ count }}
  {% endfor %}
{% endfor %}
