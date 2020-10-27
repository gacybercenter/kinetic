
## if running a full environment init, you should wipe all keys to ensure that the
## mine is empty so phase checks don't pass on old data
## They below will wipe everything that has a '-' in the minion_id, e.g.
## everything except salt and pxe

init_poweroff:
  salt.function:
    - name: system.poweroff
    - tgt: '*-*'

## This gives hosts that were givena shutdown order the ability to shut down
## There have been cases where a zeroize reset command was issued before a
## successful shutdown
init_sleep:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 30

wipe_init_keys:
  salt.wheel:
    - name: key.delete
    - match: '*-*'

## Start a runner for every endpoint type.  Whether or not this runner actually does anything is determined
## in the waiting room
{% for type in pillar['hosts'] if salt['pillar.get']('hosts:'+type+':enabled', 'True') == True %}
  {% if pillar['hosts'][type]['style'] == 'physical' %}
    {% set role = pillar['hosts'][type]['role'] %}
  {% else %}
    {% set role = type %}
  {% endif %}

create_{{ type }}_exec_runner:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/waiting_room
        pillar:
          type: {{ type }}
          needs: {{ salt['pillar.get']('hosts:'+role+':needs', {}) }}
    - parallel: true

{{ type }}_origin_phase_runner_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 1

{% endfor %}
