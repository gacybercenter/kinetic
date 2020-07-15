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
        interval: 1
        attempts: 2
        splay: 1
    - parallel: True
    - require_in:
      - {{ type }}_signal_start
    - onfail_in:
      - {{ type }}_signal_nostart

{{ type }}_{{ targetPhase }}_{{ nType }}_phase_check_loop_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 1
  {% endfor %}
{% endfor %}

## dummy placeholder for some kind of secondary retry mechanism
{{ type }}_signal_nostart:
  salt.function:
    - name: log.error
    - tgt: salt
    - arg:
        - {{ type }} failed to start the orch routine!

## dummy placeholder for actual calling of orch.generate
{{ type }}_signal_start:
  salt.function:
    - name: log.info
    - tgt: salt
    - kwarg:
        message: {{ type }} is starting the orch routine!
