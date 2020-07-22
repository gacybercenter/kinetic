{% set nType = pillar['nType'] %}
{% set nDict = pillar['nDict'] %}


{% if salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|length == 0 %}

  {% do salt.log.warning("No endpoints of type "+nType+" are available for phase checks.  Will retry...") %}

dummt_returner:
  salt.runner:
    - name: test.stream

{% else %}

  {% for host, currentPhase in salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|dictsort() %}
    {% if nDict[nType] == currentPhase|string() %}

returner:
  salt.function:
    - name: test.true
    - tgt: salt

    {% else %}

returner:
  salt.function:
    - name: test.true
    - tgt: salt

    {% endif %}
  {% endfor %}
{% endif %}
