

## Start a runner for every endpoint type.  Whether or not this runner actually does anything is determined
## in the waiting room
{% for type in pillar['hosts'] %}
create_{{ type }}_origin_phase_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/phasewait
        pillar:
          type: {{ type }}
          needs: {{ salt['pillar.get']('hosts:'+type+':needs', {}) }}
    - parallel: true

create_{{ type }}_origin_exec_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/waiting_room
        pillar:
          type: {{ type }}
    - parallel: true

{{ type }}_origin_runner_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 1
{% endfor %}
