{% set type = pillar['type'] %}
{% set hosts = salt.saltutil.runner('mine.get', tgt='pxe', fun='minionmanage.populate_'+type)['pxe'] %}

{% for host in hosts %}

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

{% for host in hosts %}

apply_base_{{ host }}:
  salt.state:
    - tgt: '{{ host }}'
    - sls:
      - formulas/common/base
    - require:
      - wait_for_minion_first_start_{{ host }}

apply_networking_{{ host }}:
  salt.state:
    - tgt: '{{ host }}'
    - sls:
      - formulas/common/networking
    - require:
      - apply_base_{{ host }}

reboot_{{ host }}:
  salt.function:
    - tgt: '{{ host }}'
    - name: system.reboot
    - kwarg:
        at_time: 1
    - require:
      - apply_networking_{{ host }}

{% endfor %}

wait_for_{{ type }}_reboot:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
{% for host in hosts %}
      - {{ host }}
{% endfor %}
    - require:
{% for host in hosts %}
      - reboot_{{ host }}
{% endfor %}
    - timeout: 600

highstate_{{ type }}:
  salt.state:
    - tgt: '{{ type }}*'
    - highstate: True
    - require:
      - highstate_{{ type }}
