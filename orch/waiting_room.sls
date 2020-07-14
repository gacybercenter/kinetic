{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}

## Check the state of the deps for this service
## Variable contents:
## needs: full dictionary passed in from init.
##    needs:
##      configure:
##        foo: install
##        bar: configure
## phase: the title of a dictionary that contains the requirements to reach the phase for that type
## nDict: the dictionary contents of the phase dictionary, looks like so:
##  foo: install
##  bar: configure
## nType: The need type.  In the above example, it would be foo and bar
## nDict[nType]: The state needed for nType to satisfy that dependency.
## in the above example, it would be install for foo and configure for bar

{% for phase, nDict in needs.items() %}
  {% for nType in nDict %}
{{ type }}_{{ phase }}_{{ nType }}_waiting_room_sleep:
  salt.runner:
    - name: compare.string
    - arg:
      - foo
      - bar
    - retry:
        interval: 2
        attempts: 3
  {% endfor %}
{% endfor %}

# {% for phase, nDict in needs.items() %}
#   {% for nType in nDict %}
# {{ type }}_{{ phase }}_{{ nType }}_waiting_room_sleep:
#   salt.function:
#     - name: cmd.run
#     - tgt: salt
#     - arg:
#       - echo {{ phase }} for {{ type }} requires that {{ nType }} reach {{ nDict[nType] }}
#   {% endfor %}
# {% endfor %}
