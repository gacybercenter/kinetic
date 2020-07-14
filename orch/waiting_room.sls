{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}

## Check the state of the deps for this service
{% for phase in needs %}
{{ type }}_{{ phase }}_waiting_room_sleep:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ phase|dictsort }}
{% endfor %}
