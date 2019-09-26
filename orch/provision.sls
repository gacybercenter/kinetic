{% set type = pillar['type'] %}
{% set hosts = salt.saltutil.runner('mine.get', tgt='pxe', fun='minionmanage.populate_'+type)['pxe'] %}
{% set target = pillar['target'] %}

## There is an inotify beacon sitting on the pxe server
## that watches our custom function write the issued hostnames
## to a directory.  Once the required amount of hostnames have
## been issued, thie mine data of all the hostnames is used
## to watch the provisioning process.  We allow 30 minutes to
## install the operating system.  This is probably excessive.





wait_for_{{ target }}_hostname_assignment:
  salt.wait_for_event:
    - name: salt/job/*/ret/pxe
    - event_id: fun
    - id_list:
      - mine.send
    - timeout: 600



wait_for_provisioning_{{ host }}:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ host }}
    - timeout: 1200

accept_minion_{{ host }}:
  salt.wheel:
    - name: key.accept
    - match: {{ host }}
    - require:
      - wait_for_provisioning_{{ host }}

wait_for_minion_first_start_{{ host }}:
  salt.wait_for_event:
    - name: salt/minion/{{ host }}/start
    - id_list:
      - {{ host }}
    - timeout: 60
    - require:
      - accept_minion_{{ host }}

remove_pending_{{ host }}:
  salt.function:
    - name: file.remove
    - tgt: 'pxe'
    - arg:
      - /var/www/html/pending_hosts/{{ type }}/{{ host }}
    - require:
      - wait_for_minion_first_start_{{ host }}

{% endfor %}

apply_base_{{ type }}:
  salt.state:
    - tgt: '{{ type }}*'
    - sls:
      - formulas/common/base

apply_networking_{{ type }}:
  salt.state:
    - tgt: '{{ type }}*'
    - sls:
      - formulas/common/networking
    - require:
      - apply_base_{{ type }}

reboot_{{ type }}:
  salt.function:
    - tgt: '{{ type }}*'
    - name: system.reboot
    - kwarg:
        at_time: 1
    - require:
      - apply_networking_{{ type }}

wait_for_{{ type }}_reboot:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
{% for host in hosts %}
      - {{ host }}
{% endfor %}
    - require:
      - reboot_{{ type }}
    - timeout: 600

highstate_{{ type }}:
  salt.state:
    - tgt: '{{ type }}*'
    - highstate: True
    - require:
      - wait_for_{{ type }}_reboot
