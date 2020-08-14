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

## This loop will continuously re-check the state of the dependencies
## It can probably be simplified significantly as a dependency check is also
## built in to the generate function

{{ type }}_phase_check_init:
  salt.runner:
    - name: needs.check_all
    - kwarg:
        needs: {{ needs }}
        type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10

{{ type }}_generate_start_signal:
  salt.runner:
    - name: event.send
    - kwarg:
        tag: {{ type }}/generate/auth/start
        data:
          id: {{ type }}
    - require:
      - {{ type }}_phase_check_init
