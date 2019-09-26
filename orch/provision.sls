{% set type = pillar['type'] %}
{% set target = pillar['target'] %}
{% set uuid = pillar['uuid'] %}

## There is an inotify beacon sitting on the pxe server
## that watches our custom function write the issued hostnames
## to a directory.  Once the required amount of hostnames have
## been issued, thie mine data of all the hostnames is used
## to watch the provisioning process.  We allow 30 minutes to
## install the operating system.  This is probably excessive.

assign_uuid_to_{{ target }}:
  salt.function:
    - name: file.write
    - tgt: 'pxe'
    - arg:
      - /var/www/html/assignments/{{ target }}
      - {{ type }}-{{ uuid }}

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

remove_pending_{{ type }}-{{ uuid }}}:
  salt.function:
    - name: file.remove
    - tgt: 'pxe'
    - arg:
      - /var/www/html/assignments/{{ target }}
    - require:
      - wait_for_minion_first_start_{{ type }}-{{ uuid }}
