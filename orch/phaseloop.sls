{% set nType = pillar['nType'] %}
{% set nDict = pillar['nDict'] %}


{% if salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|length == 0 %}

  {% do salt.log.warning("No endpoints of type "+nType+" are available for phase checks.  Will retry...") %}

returner:
  salt.function:
    - name: test.false
    - tgt: salt

{% else %}

  {% for host, currentPhase in salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|dictsort() %}

check_{{ nType }}_{{ host }}:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: {{ nDict['nType'] }}
        currentString: {{ currentPhase }}
    - retry:
        interval: 1
        times: 2
        splay: 0

  {% endfor %}
{% endif %}
