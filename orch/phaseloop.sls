{% set nType = pillar['nType'] %}
{% set nDict = pillar['nDict'] %}


{% if salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|length == 0 %}

  {% do salt.log.warning("No endpoints of type"+nType+" are available for phase checks.  Will retry...") %}

{% else %}

  {% for host, currentPhase in salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|dictsort() %}
{{ host }}_phase_check:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: {{ nDict[nType] }}
## If this check is done before build_phase has a value, it will return a Nonetype
## This should probably be changed to grains.get instead of grains.item in the mine def
        currentString: {{ currentPhase|string }}
  {% endfor %}
{% endif %}
