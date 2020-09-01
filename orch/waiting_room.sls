{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}

## This is the maximum amount of time an endpoint should wait for the start
## signal. It will need to be at least two hours (generally).  Less is
## fine for testing
{{ type }}_phase_check_init:
  salt.runner:
    - name: needs.check_all
    - kwarg:
        needs: {{ needs }}
        type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 60

{% do salt.log.info(type+" initialization routine is aboue to begin!") %}

orch_{{ type }}_init_exec_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/generate
        pillar:
          type: {{ type }}
    - require:
      - {{ type }}_phase_check_init
