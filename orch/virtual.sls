master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true

{% for type in pillar['virtual'] %}
{% set count = pillar['virtual'][type]['count'] %}

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

select_{{ type }}_controllers:
  salt.runner:
    - name: manage.up
    - kwarg:
        tgt_type: grain
        tgt:
          role:controller
        out-file: /root/foo3

parallel_deploy_{{ type }}:
  salt.parallel_runners:
    - runners:
  {% for host in range(count) %}
        runner_{{ host }}:
          - name: state.orchestrate
          - kwarg:
              mods: orch/create_instances
              pillar:
                type: {{ type }}
                target: __slot__:salt:cmd.run("shuf -n 1 /root/foo")
  {% endfor %}
{% endfor %}
