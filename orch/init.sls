

## Start a runner for every endpoint type.  Whether or not this runner actually does anything is determined later
{% for type in pillar['hosts'] %}
create_type_origin_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/waiting_room
        pillar:
          type: {{ type }}
    - parallel: true

{{ type }}_origin_runner_delay:
  salt.runner:
    - name: test.sleep
    - kwarg:
        s_time: 1
{% endfor %}
