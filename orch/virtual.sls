{% set type = pillar['type'] %}
{% set count = pillar['virtual'][type]['count'] %}


{% for host in range(count) %}
create_{{ type }}_{{ host }}:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/create_instances
        pillar:
          type: {{ type }}
          target: __slot__:salt:cmd.run("shuf -n 1 /tmp/{{ type }}_available_controllers")
          spawning: {{ loop.index0 }}
    - parallel: true

sleep_{{ type }}_{{ host }}:
  salt.function:
    - name: cmd.run
    - tgt: 'salt'
    - arg:
      - sleep 1
{% endfor %}
