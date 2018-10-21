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
    - require:
      - apply_networking_{{ host }}

{% endfor %}

{% for host in hosts %}

wait_for_reboot_{{ host }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
      - {{ host }}
    - require:
      - reboot_{{ host }}
    - timeout: 300

{% endfor %}

parallel-highstate:
  salt.parallel_runners:
    - runners:
{% for host in hosts %}
        minion_setup_{{ host }}:
          - name: state.orchestrate
          - kwarg:
              mods: orch/highstate
              pillar:
                host: {{ host }}
{% endfor %}  
