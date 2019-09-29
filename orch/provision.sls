{% set type = pillar['type'] %}
{% set target = pillar['target'] %}
{% set style = pillar['types'][type] %}
{% set uuid = 4294967296 | random_hash | uuid %}

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
      - {{ type }}-{{ uuid }}

{% elif style == 'virtual' %}
{% set spawning = salt['pillar.get']('spawning', '0') %}
get_available_controllers_for_{{ type }}-{{ uuid }}:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - salt-run manage.up tgt_type="grain" tgt="role:controller" | sed 's/^..//' > /tmp/{{ type }}-{{ uuid }}_available_controllers

prepare_vm_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: __slot__:salt:cmd.run("shuf -n 1 /tmp/{{ type }}-{{ uuid }}_available_controllers")
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

{% if style == 'physical' %}
remove_pending_{{ type }}-{{ uuid }}:
  salt.function:
    - name: file.remove
    - tgt: 'pxe'
    - arg:
      - /var/www/html/assignments/{{ target }}
    - require:
      - wait_for_minion_first_start_{{ type }}-{{ uuid }}

{% elif style == 'virtual' %}
run_once_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/common/runonce
    - require:
      - wait_for_minion_first_start_{{ type }}-{{ uuid }}

run_once_reboot_{{ type }}-{{ uuid }}:
  salt.function:
    - tgt: '{{ type }}-{{ uuid }}'
    - name: system.reboot
    - kwarg:
        at_time: 1
    - require:
      - run_once_{{ type }}-{{ uuid }}

wait_for_run_once_reboot_{{ type }}-{{ uuid }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ type }}-{{ uuid }}
    - require:
      - run_once_reboot_{{ type }}-{{ uuid }}
    - timeout: 300

set_spawning_{{ type }}-{{ uuid }}:
  salt.function:
    - name: grains.set
    - tgt: '{{ type }}-{{ uuid }}'
    - arg:
      - spawning
    - kwarg:
          val: {{ spawning }}
    - require:
      - wait_for_run_once_reboot_{{ type }}-{{ uuid }}
{% endif %}

apply_base_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/common/base

apply_networking_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - sls:
      - formulas/common/networking
    - require:
      - apply_base_{{ type }}-{{ uuid }}

reboot_{{ type }}-{{ uuid }}:
  salt.function:
    - tgt: '{{ type }}-{{ uuid }}'
    - name: system.reboot
    - kwarg:
        at_time: 1
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

update_mine_{{ type }}-{{ uuid }}:
  salt.function:
    - name: mine.update
    - tgt: '{{ type }}-{{ uuid }}'

highstate_{{ type }}-{{ uuid }}:
  salt.state:
    - tgt: '{{ type }}-{{ uuid }}'
    - highstate: True
    - require:
      - wait_for_{{ type }}-{{ uuid }}_reboot
