{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}

## Check the state of the deps for this service
{% for phase, nDict in needs.items() %}
  {% for nType in nDict %}
{{ type }}_{{ phase }}_{{ nType }}_waiting_room_sleep:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ phase }} for {{ type }} requires that {{ nType }} reach {{ nDict[nType] }}
  {% endfor %}
{% endfor %}
