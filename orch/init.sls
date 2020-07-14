

## Start a runner for every endpoint type.  Whether or not this runner actually does anything is determined
## in the waiting room
{% for type in pillar['hosts'] %}
create_{{ type }}_origin_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/waiting_room
        pillar:
          type: {{ type }}
          needs: {{ salt['pillar.get']('hosts:'+type+':needs', {}) }}
    - parallel: true

{{ type }}_origin_runner_delay:
  salt.runner:
    - name: test.sleep
    - kwarg:
        s_time: 1
    - parallel: true
{% endfor %}
