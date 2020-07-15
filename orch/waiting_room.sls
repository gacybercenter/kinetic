{% set type = pillar['type'] %}

{% for phase in ['base', 'networking', 'install', 'configure'] %}

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
