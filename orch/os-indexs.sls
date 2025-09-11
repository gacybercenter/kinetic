{% set k8s = salt['pillar.get']('k8s', 'salt-master') %}

check_os_health:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - opensearch_states.check_os_health
    - pillar:
        admin_user: admin

create_kvm_logs_index:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - opensearch_states.create_kvm_logs_index
    - pillar:
        admin_user: admin
        index_name: kvm-logs
    - require:
      - salt: check_os_health

create_fluentbit_role:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - opensearch_states.create_fluentbit_role
    - pillar:
        admin_user: admin
        role_name: fluentbit_role
        index_name: kvm-logs
    - require:
      - salt: create_kvm_logs_index

map_fluentbit_to_role:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - opensearch_states.map_fluentbit_to_role
    - pillar:
        admin_user: admin
        role_name: fluentbit_role
        user_name: fluentbit
    - require:
      - salt: create_fluentbit_role