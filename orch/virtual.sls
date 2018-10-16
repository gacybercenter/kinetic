master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

{% for type in pillar['virtual'] %}
destroy_{{ type }}_domain:
  salt.function:
    - name: cmd.run
    - tgt: 'controller*'
    - arg:
      - virsh list | grep {{ type }} | cut -d" " -f 2 | while read id;do virsh destroy $id;done

wipe_{{ type }}_vms:
  salt.function:
    - name: cmd.run
    - tgt: 'controller*'
    - arg:
      - ls /kvm/vms | grep {{ type }} | while read id;do rm -rf /kvm/vms/$id;done  

delete_{{ type }}_key:
  salt.wheel:
    - name: key.delete
    - match: '{{ type }}*'

{% set count = pillar['virtual'][type]['count'] %}
parallel_deploy_{{ type }}:
  salt.parallel_runners:
    - runners:
  {% for host in range(count) %}
  {% set host+-identifier = salt.cmd.shell("uuidgen") %}
        {{ host }}-{{ identifier }}_runner:
          - name: state.orchestrate
          - kwarg:
              mods: orch/test_parallel_temp
              pillar:
                identifier: {{ identifier }}
                type: {{ type }}
  {% endfor %}
{% endfor %}
