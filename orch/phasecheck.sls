{% for host, currentPhase in pillar['currentPhases']|dictsort %}
{{ host }}_phase_check:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: foo
        currentString: {{ currentPhase }}
    - parallel: True
{% endfor %}
