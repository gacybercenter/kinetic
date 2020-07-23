{% set nType = pillar['nType'] %}
{% set nDict = pillar['nDict'] %}
{% set type = salt['pillar.get']('type', '') %}


{% if salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|length == 0 %}

fail_tracker_missing_{{ nType }}:
  test.fail_without_changes:
    - comment: 'No endpoints of type {{ nType }} are available for checking dependencies of type {{ type }}. This error is not fatal, will retry...'

{% else %}

  {% for host, currentPhase in salt.saltutil.runner('mine.get',tgt='role:'+nType,tgt_type='grain',fun='build_phase')|dictsort() %}
check_{{ nType }}_{{ host }}:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: {{ nDict[nType] }}
        currentString: {{ currentPhase }}
  {% endfor %}
{% endif %}
