{% set type = pillar['type'] %}
{% if pillar['hosts'][type]['style'] == 'physical' %}
  {% set role = pillar['hosts'][type]['role'] %}
{% else %}
  {% set role = type %}
{% endif %}

{% set target = pillar['target'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set controller = pillar['controller'] %}
{% set uuid =  salt['random.get_str']('64') | uuid %}

## There is an inotify beacon sitting on the pxe server
## that watches our custom function write the issued hostnames
## to a directory.  Once the required amount of hostnames have
## been issued, thie mine data of all the hostnames is used
## to watch the provisioning process.  We allow 30 minutes to
## install the operating system.  This is probably excessive.

{% if style == 'physical' %}
assign_uuid_to_{{ target }}:
  salt.function:
    - name: file.write
    - tgt: 'pxe'
    - arg:
      - /var/www/html/assignments/{{ target }}
      - {{ type }}
      - {{ type }}-{{ uuid }}
      - {{ pillar['hosts'][type]['os'] }}
      - {{ pillar['hosts'][type]['interface'] }}

## Need to spawn a listeniner (http? tcp?) that will wait for
## generated physical endpoints to send it a signal once they have
## successfully pulled initrd and the kernel.  It's fairly common
## for several physical hosts to fail kernel retrieval when there
## are a large number.

## alternative option is building in a retry into ipxe (if supported)?

{% elif style == 'virtual' %}
{% set spawning = salt['pillar.get']('spawning', '0') %}

prepare_vm_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: {{ controller }}
    - sls:
      - orch/states/virtual_prep
    - pillar:
        hostname: {{ type }}-{{ uuid }}
    - concurrent: true
{% endif %}

wait_for_provisioning_{{ type }}-{{ uuid }}:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ type }}-{{ uuid }}
    - timeout: 1200

accept_minion_{{ type }}-{{ uuid }}:
  salt.wheel:
    - name: key.accept
    - match: {{ type }}-{{ uuid }}
    - require:
      - wait_for_provisioning_{{ type }}-{{ uuid }}

wait_for_minion_first_start_{{ type }}-{{ uuid }}:
  salt.wait_for_event:
    - name: salt/minion/{{ type }}-{{ uuid }}/start
    - id_list:
      - {{ type }}-{{ uuid }}
    - timeout: 60
    - require:
      - accept_minion_{{ type }}-{{ uuid }}

sync_all_{{ type }}-{{ uuid }}:
  salt.function:
    - name: saltutil.sync_all
    - tgt: '{{ type }}-{{ uuid }}'
    - require:
      - wait_for_minion_first_start_{{ type }}-{{ uuid }}

{% if style == 'physical' %}
remove_pending_{{ type }}-{{ uuid }}:
  salt.function:
    - name: file.remove
    - tgt: 'pxe'
    - arg:
      - /var/www/html/assignments/{{ target }}
    - require:
      - sync_all_{{ type }}-{{ uuid }}

{% elif style == 'virtual' %}
set_spawning_{{ type }}-{{ uuid }}:
  salt.function:
    - name: grains.set
    - tgt: '{{ type }}-{{ uuid }}'
    - arg:
      - spawning
    - kwarg:
          val: {{ spawning }}
    - require:
      - sync_all_{{ type }}-{{ uuid }}
{% endif %}

apply_base_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/common/base

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
        attempts: 10
        splay: 10
    - require_in:
      - apply_networking_{{ type }}-{{ uuid }}
{% endfor %}

apply_networking_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/common/networking
    - failhard: True
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

{% if (salt['pillar.get']('spawning', '0')|int != 0) and (style == 'virtual') %}

wait_for_spawning_0_{{ type }}-{{ uuid }}:
  salt.wait_for_event:
    - name: {{ type }}/spawnzero/complete
    - id_list:
      - {{ type }}/spawnzero/complete
    - event_id: tag
    - timeout: 600
    - require:
      - wait_for_{{ type }}-{{ uuid }}_reboot

{% endif %}

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
        attempts: 10
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
        attempts: 10
        splay: 10
    - require_in:
      - highstate_{{ type }}-{{ uuid }}
{% endfor %}

highstate_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - highstate: True
    - timeout: 600
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
    - arg:
      - production
      - True
