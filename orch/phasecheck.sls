{% set nType = pillar['nType'] %}
{% set nDict = pillar['nDict'] %}

{% for host, currentPhase in salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|dictsort() %}
{{ host }}_phase_check:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: {{ nDict[nType] }}
        currentString: {{ currentPhase }}
{% endfor %}
