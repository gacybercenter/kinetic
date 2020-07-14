{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}

## Check the state of the deps for this service
{% for phase in needs %}
  {% for nType, nState in pillar['hosts'][type]['needs'][phase] %}
{{ type }}_{{ phase }}_waiting_room_sleep:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }} needs {{ nType }} to reach {{ nState }} to be able to reach {{ phase }}
  {% endfor %}
{% endfor %}
