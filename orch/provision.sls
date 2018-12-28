{% set type = pillar['type'] %}
{% set hosts = salt.saltutil.runner('mine.get', tgt='pxe', fun='minionmanage.populate_'+type)['pxe'] %}

{% for host in hosts %}

wait_for_provisioning_{{ host }}:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
      - {{ host }}
    - timeout: 1800

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
