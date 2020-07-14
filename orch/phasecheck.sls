{% for host, currentPhase in {{ salt.saltutil.runner('mine.get',tgt='role:'+pillar['nType'],tgt_type='grain',fun='build_phase') }} %}
{{ host }}_phase_check:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: {{ pillar['nDict'][pillar['nType']] }}
        currentString: {{ currentPhase }}
    - parallel: True
{% endfor %}
