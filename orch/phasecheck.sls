{% set nDict = pillar['nDict'] %}
{% set targetPhase = pillar['targetPhase'] %}
{% set type = pillar['type'] %}

{% for nType in nDict %}
{{ type }}_{{ targetPhase}}_{{ nType }}_phase_check_loop:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/phaseloop
        pillar:
          nDict: {{ nDict }}
          nType: {{ nType }}
    - parallel: True

{{ type }}_{{ targetPhase }}_{{ nType }}_phase_check_loop_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 1
{% endfor %}
