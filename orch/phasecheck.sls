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
    - retry:
        interval: 30
        times: 60
        splay: 10
    - require_in:
      - {{ type }}_generate_start_signal

{% endfor %}

{{ type }}_generate_start_signal:
  salt.runner:
    - name: event.send
    - kwarg:
        tag: {{ type }}/generate/auth/start
        data:
          id: {{ type }}
