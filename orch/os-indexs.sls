check_os_health:
  opensearch.cluster_healthy:
    - name: check_os_health
    - admin_user: admin

create_kvm_logs_index:
  opensearch.index_present:
    - name: create_kvm_logs_index
    - index_name: kvm-logs
    - admin_user: admin
    - require:
      - opensearch: check_os_health

create_fluentbit_role:
  opensearch.role_present:
    - name: create_fluentbit_role
    - role_name: fluentbit_role
    - index_name: kvm-logs
    - admin_user: admin
    - require:
      - opensearch: create_kvm_logs_index

map_fluentbit_to_role:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_to_role
    - role_name: fluentbit_role
    - user_name: fluentbit
    - admin_user: admin
    - require:
      - opensearch: create_fluentbit_role