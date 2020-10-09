## This routine is called on a fresh minion whose key was just accepted.

{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set targets = pillar['targets'] %}

{% if pillar['hosts'][type]['style'] == 'physical' %}
  {% set role = pillar['hosts'][type]['role'] %}
{% else %}
  {% set role = type %}
{% endif %}

apply_base_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
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
{% if salt['pillar.get']('hosts:'+type+':needs:networking', {}) != {} %}
{{ type }}_networking_phase_check_loop::
  salt.runner:
    - name: needs.check_one
    - kwarg:
        needs: {{ salt['pillar.get']('hosts:'+type+':needs:networking', {}) }}
        type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - apply_networking_{{ type }}
{% endif %}

apply_networking_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/common/networking
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - apply_base_{{ type }}

set_build_phase_networking_{{ type }}:
  salt.function:
    - name: grains.setval
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - arg:
      - build_phase
      - networking
    - require:
      - apply_networking_{{ type }}

set_build_phase_networking_mine_{{ type }}:
  salt.function:
    - name: mine.update
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - require:
      - set_build_phase_networking_{{ type }}

reboot_{{ type }}:
  salt.function:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - name: system.reboot
    - require:
      - apply_networking_{{ type }}

wait_for_{{ type }}_reboot:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - require:
      - reboot_{{ type }}
    - timeout: 600

force_network_mine_refresh_{{ type }}:
  salt.function:
    - name: mine.update
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - require:
      - wait_for_{{ type }}_reboot

{% if salt['pillar.get']('hosts:'+type+':needs:install', {}) != {} %}
{{ type }}_install_phase_check_loop:
  salt.runner:
    - name: needs.check_one
    - kwarg:
        needs: {{ salt['pillar.get']('hosts:'+type+':needs:install', {}) }}
        type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - apply_install_{{ type }}
{% endif %}

apply_install_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - sls:
      - formulas/{{ role }}/install
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - wait_for_{{ type }}_reboot

set_build_phase_install_{{ type }}:
  salt.function:
    - name: grains.setval
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - arg:
      - build_phase
      - install
    - require:
      - apply_install_{{ type }}

set_build_phase_install_mine_{{ type }}:
  salt.function:
    - name: mine.update
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - require:
      - set_build_phase_install_{{ type }}

{% if salt['pillar.get']('hosts:'+type+':needs:configure', {}) != {} %}
{{ type }}_configure_phase_check_loop:
  salt.runner:
    - name: needs.check_one
    - kwarg:
        needs: {{ salt['pillar.get']('hosts:'+type+':needs:configure', {}) }}
        type: {{ type }}
    - retry:
        interval: 30
        attempts: 240
        splay: 10
    - require_in:
      - highstate_{{ type }}
{% endif %}

highstate_{{ type }}:
  salt.state:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - highstate: True
    - timeout: 600
    - retry:
        interval: 10
        attempts: 2
        splay: 0
    - require:
      - apply_install_{{ type }}

final_reboot_{{ type }}:
  salt.function:
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - name: system.reboot
    - require:
      - highstate_{{ type }}

wait_for_final_reboot_{{ type }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - require:
      - final_reboot_{{ type }}
    - timeout: 600

set_build_phase_configure_{{ type }}:
  salt.function:
    - name: grains.setval
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - arg:
      - build_phase
      - configure
    - require:
      - highstate_{{ type }}

set_build_phase_configure_mine_{{ type }}:
  salt.function:
    - name: mine.update
    - tgt:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - tgt_type: list
    - require:
      - set_build_phase_configure_{{ type }}
