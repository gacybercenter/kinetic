{% set type = pillar['type'] %}

## This is the maximum amount of time an endpoint should wait for the start
## signal. It will need to be at least two hours (generally).  Less is
## fine for testing
wait_for_start_authorization_{{ type }}:
  salt.wait_for_event:
    - name: {{ type }}/generation/auth/start
    - id_list:
      - {{ type }}
    - timeout: 1800

{{ type }}_{{ phase }}_exec:
  salt.runner:
    - name: test.sleep
    - kwarg:
        s_time: 1
    - require:
      - wait_for_start_authorization_{{ type }}

orch_{{ type }}_init_exec_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/generate
        pillar:
          type: {{ type }}
    - require:
      - wait_for_start_authorization_{{ type }}
