master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

{% for type in pillar['virtual'] %}
  {% set count = pillar['virtual'][type]['config']['count'] %}
  {% for host in range(count) %}
  {% set identifier = salt.cmd.shell("uuidgen") %}

func_create_{{ type}}_{{ host }}:
  salt.function:
    - name: cmd.run
    - tgt: salt
    - arg:
      - echo {{ type }} {{ count }}

prepare_vm:
  salt.state:
    - tgt: controller*
    - sls:
      - orch/states/virtual_prep


  {% endfor %}
{% endfor %}
