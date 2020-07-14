{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}

## Check the state of the deps for this service
{% for phase in needs %}
  {% for nType in phase %}
{{ type }}_waiting_room_sleep:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }} needs {{ nType }} to be {{ needs }} to reach {{ phase }}
  {% endfor %}
{% endfor %}
