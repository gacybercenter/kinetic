{% set type = pillar['type'] %}
{% set needs = pillar['needs'] %}

## Check the state of the deps for this service


## sample dictionary
## ...
##    needs:
##      install:
##        qux: configure
##        baz: configure
##      configure:
##        foo: install
##        bar: configure
##
## targetPhase: the title of the dictionary that contains the requirements to reach the phase for that type
##              in the above example, it would be 'configure' and 'install'

## nDict: the dictionary contents of the phase dictionary.  In the above example, it would be
##        install:
##          qux: configure
##          baz: configure
##
##  and
##
##        configure:
##          foo: install
##          bar: configure
##
## presented as separate objects in a loop
##
## nType: The need type.  In the above example, it would be qux, baz, foo, and bar, presented in their respective loops
## nDict[nType]: The state needed for nType to satisfy that dependency (base, networking, install, or configure).

{% for targetPhase, nDict in needs.items() %}
  {% for nType in nDict %}
{{ type }}_{{ targetPhase }}_{{ nType }}_phase_check_loop:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/phasecheck
        pillar:
          nDict: {{ nDict }}
          nType: {{ nType }}
    - retry:
        interval: 3
        attempts: 3
        splay: 5
    - parallel: True
    - require_in:
      - {{ type }}_signal_start

{{ type }}_origin_runner_delay:
  salt.runner:
    - name: test.sleep
    - kwarg:
        s_time: 1      
  {% endfor %}
{% endfor %}

{{ type }}_signal_start:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }} is starting the orch routine!
