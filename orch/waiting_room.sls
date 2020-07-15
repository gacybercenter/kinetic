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
        interval: 0
        attempts: 1
        splay: 0
    - require_in:
      - {{ type }}_{{ targetPhase }}_start_signal

{{ type }}_{{ targetPhase }}_phase_check_init_delay:
  salt.function:
    - name: test.sleep
    - tgt: salt
    - kwarg:
        length: 1

{{ type }}_{{ targetPhase }}_start_signal:
  salt.runner:
    - name: event.send
    - kwarg:
        tag: {{ type }}/{{ targetPhase }}/auth/start
        data: '{"id": "{{ targetPhase }}"}'

{% endfor %}

{% for phase in ['configure'] %}

wait_for_start_authorization_{{ type }}-{{ phase }}:
  salt.wait_for_event:
    - name: {{ type }}/{{ phase }}/auth/start
    - id_list:
      - {{ phase }}
    - timeout: 30

{{ type }}_{{ phase }}_exec:
  salt.runner:
    - name: test.sleep
    - kwarg:
        s_time: 1

{% endfor %}
