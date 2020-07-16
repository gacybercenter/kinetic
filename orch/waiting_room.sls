{% set type = pillar['type'] %}
{% set phase = pillar['phase'] %}


### This is gross.  Find a way to do this better
### Goal is for higher level phases to automatically
### resolve all lower level dependencies if they themselves
### get resolved.  This prevents the need for manual definition
### of all phase dependencies
{% if phase == 'configure' %}
  {% set children = ['install', 'networking', 'base'] %}
{% elif phase == 'install' %}
  {% set children = ['networking', 'base'] %}
{% elif phase == 'networking' %}
  {% set children = ['base'] %}
{% else %}
  {% set children = [] %}
{% endif %}
### /gross

wait_for_start_authorization_{{ type }}-{{ phase }}:
  salt.wait_for_event:
    - name: {{ type }}/{{ phase }}/auth/start
    - id_list:
      - {{ phase }}
    - timeout: 30

{% for child in children %}
{{ type }}_{{ child }}_start_signal:
  salt.runner:
    - name: event.send
    - kwarg:
        tag: {{ type }}/{{ child }}/auth/start
        data:
          id: {{ child }}
    - require:
      - wait_for_start_authorization_{{ type }}-{{ phase }}
{% endfor %}

{{ type }}_{{ phase }}_exec:
  salt.runner:
    - name: test.sleep
    - kwarg:
        s_time: 1
