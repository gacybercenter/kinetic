{% set nType = pillar['nType'] %}
{% set nDict = pillar['nDict'] %}


{% if salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|length == 0 %}

returner:
  salt.function:
    - name: log.warning
    - tgt: salt
    - kwarg:
        message: "blah blah"

{% else %}

  {% for host, currentPhase in salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|dictsort() %}

check_{{ nType }}_{{ host }}:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: {{ nDict[nType] }}
        currentString: {{ currentPhase }}
    - retry:
        interval: 30
        times: 60
        splay: 0

  {% endfor %}
{% endif %}
