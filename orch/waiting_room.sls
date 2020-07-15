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
{{ type }}_{{ targetPhase }}_phase_check_init:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/phasecheck
        pillar:
          nDict: {{ nDict }}
          targetPhase: {{ targetPhase }}
          type: {{ type }}
    - parallel: True
    - retry:
        interval: 3
        attempts: 2
        splay: 5

{{ type }}_{{ targetPhase }}_phase_check_init_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 2

{{ type }}_{{ targetPhase }}_signal_start:
  salt.function:
    - name: log.info
    - tgt: salt
    - kwarg:
        message: {{ type }} is starting the {{ targetPhase}} phase!
    - require:
      - {{ type }}_{{ targetPhase }}_phase_check_init
    - require_in:
      - {{ type }}_signal_start

{{ type }}_{{ targetPhase }}_signal_fail:
  salt.function:
    - name: log.error
    - tgt: salt
    - kwarg:
        message: {{ type }} failed to start the {{ targetPhase}} phase!
    - onfail:
      - {{ type }}_{{ targetPhase }}_phase_check_init
    - onfail_in:
      - {{ type }}_signal_nostart

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
