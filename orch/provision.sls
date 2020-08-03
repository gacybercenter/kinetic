## This routine is called on a fresh minion whose key was just accepted.

{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set uuid =  pillar['uuid'] %}

{% if pillar['hosts'][type]['style'] == 'physical' %}
  {% set role = pillar['hosts'][type]['role'] %}
{% else %}
  {% set role = type %}
{% endif %}


apply_base_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/common/base
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0

### This loop will block until confirmation is received that all networking
### deps have been met.  The logic is very similar to the initial dep check loop
### adding an additional one here will ensure that the deps needed for the
### next phase of the orch have been met, rather than just the bits needed to
### start
{% for nType in salt['pillar.get']('hosts:'+type+':needs:networking', {}) %}
{{ type }}_networking_{{ nType }}_phase_check_loop:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/phaseloop
        pillar:
          nDict: {{ salt['pillar.get']('hosts:'+type+':needs:networking', {}) }}
          nType: {{ nType }}
          type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - apply_networking_{{ type }}-{{ uuid }}
{% endfor %}

apply_networking_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/common/networking
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - apply_base_{{ type }}-{{ uuid }}

set_build_phase_networking_{{ type }}-{{ uuid }}:
  salt.function:
    - name: grains.setval
    - tgt: '{{ type }}-{{ uuid }}'
    - arg:
      - build_phase
      - networking
    - require:
      - apply_networking_{{ type }}-{{ uuid }}

set_build_phase_networking_mine_{{ type }}-{{ uuid }}:
  salt.function:
    - name: mine.update
    - tgt: '{{ type }}-{{ uuid }}'
    - require:
      - set_build_phase_networking_{{ type }}-{{ uuid }}

reboot_{{ type }}-{{ uuid }}:
  salt.function:
    - tgt: '{{ type }}-{{ uuid }}'
    - name: system.reboot
    - require:
      - apply_networking_{{ type }}-{{ uuid }}

wait_for_{{ type }}-{{ uuid }}_reboot:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ type }}-{{ uuid }}
    - require:
      - reboot_{{ type }}-{{ uuid }}
    - timeout: 600

{% for nType in salt['pillar.get']('hosts:'+type+':needs:install', {}) %}
{{ type }}_install_{{ nType }}_phase_check_loop:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/phaseloop
        pillar:
          nDict: {{ salt['pillar.get']('hosts:'+type+':needs:install', {}) }}
          nType: {{ nType }}
          type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - apply_install_{{ type }}-{{ uuid }}
{% endfor %}

apply_install_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/{{ role }}/install
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - wait_for_{{ type }}-{{ uuid }}_reboot

set_build_phase_install_{{ type }}-{{ uuid }}:
  salt.function:
    - name: grains.setval
    - tgt: '{{ type }}-{{ uuid }}'
    - arg:
      - build_phase
      - install
    - require:
      - apply_install_{{ type }}-{{ uuid }}

set_build_phase_install_mine_{{ type }}-{{ uuid }}:
  salt.function:
    - name: mine.update
    - tgt: '{{ type }}-{{ uuid }}'
    - require:
      - set_build_phase_install_{{ type }}-{{ uuid }}

{% for nType in salt['pillar.get']('hosts:'+type+':needs:configure', {}) %}
{{ type }}_configure_{{ nType }}_phase_check_loop:
  salt.runner:
    - name: state.orchestrate
    - kwarg:
        mods: orch/phaseloop
        pillar:
          nDict: {{ salt['pillar.get']('hosts:'+type+':needs:configure', {}) }}
          nType: {{ nType }}
          type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - highstate_{{ type }}-{{ uuid }}
{% endfor %}

{% if (salt['pillar.get']('spawning', '0')|int != 0) and (style == 'virtual') %}
  {% for host, spawnzero_complete in salt.saltutil.runner('mine.get',tgt='G@role:'+type+' and G@spawning:0',tgt_type='compound',fun='spawnzero_complete')|dictsort() %}
spawnzero_check_{{ type }}_{{ host }}:
  salt.runner:
    - name: compare.string
    - kwarg:
        targetString: True
        currentString: {{ spawnzero_complete }}
    - retry:
        interval: 5
        attempts: 30
        splay: 0
    - require_in:
      - highstate_{{ type }}-{{ uuid }}
  {% endfor %}
{% endif %}

highstate_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - highstate: True
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - apply_install_{{ type }}-{{ uuid }}

final_reboot_{{ type }}-{{ uuid }}:
  salt.function:
    - tgt: '{{ type }}-{{ uuid }}'
    - name: system.reboot
    - require:
      - highstate_{{ type }}-{{ uuid }}

wait_for_final_reboot_{{ type }}-{{ uuid }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ type }}-{{ uuid }}
    - require:
      - final_reboot_{{ type }}-{{ uuid }}
    - timeout: 600

set_build_phase_configure_{{ type }}-{{ uuid }}:
  salt.function:
    - name: grains.setval
    - tgt: '{{ type }}-{{ uuid }}'
    - arg:
      - build_phase
      - configure
    - require:
      - highstate_{{ type }}-{{ uuid }}

set_build_phase_configure_mine_{{ type }}-{{ uuid }}:
  salt.function:
    - name: mine.update
    - tgt: '{{ type }}-{{ uuid }}'
    - require:
      - set_build_phase_configure_{{ type }}-{{ uuid }}

set_production_{{ type }}-{{ uuid }}:
  salt.function:
    - name: grains.setval
    - tgt: '{{ type }}-{{ uuid }}'
    - require:
      - highstate_{{ type }}-{{ uuid }}    
    - arg:
      - production
      - True
