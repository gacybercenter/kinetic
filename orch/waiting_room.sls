{% set type = pillar['type'] %}

## This is the maximum amount of time an endpoint should wait for the start
## signal. It will need to be at least two hours (generally).  Less is
## fine for testing
wait_for_start_authorization_{{ type }}:
  salt.wait_for_event:
    - name: {{ type }}/generate/auth/start
    - id_list:
      - {{ type }}
    - timeout: 7200

{% do salt.log.info(type+" initialization routine is aboue to begin!") %}

orch_{{ type }}_init_exec_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/generate
        pillar:
          type: {{ type }}
    - require:
      - wait_for_start_authorization_{{ type }}
