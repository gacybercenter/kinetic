include:
  - /formulas/common/k8s-efk/install

# State formula to configure OpenSearch for logging with Fluent Bit
# Ensures cluster health and sets up roles for Fluent Bit user access
check_opensearch_health:
  opensearch.cluster_health:
    - name: check_opensearch_health
    - admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
    - admin_password: {{ pillar.get('opensearch_admin_password') }}
    - host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
    - require:
      - k8s: opensearch_cluster_cr

# Create or update the log_writer OpensearchRole CR with permissions for index creation and writing
update_log_writer_role:
  opensearch.role_present:
    - name: update_log_writer_role
    - role_name: log_writer
    - index_name: openldap-audit-logs-  # Matches openldap-audit-logs-* pattern in kinetic-os.create_role
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - opensearch: check_opensearch_health

# Map the fluentbit user to the log_writer role for write access (OpensearchUserRoleBinding CR)
map_fluentbit_user_to_log_writer:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_log_writer_role
    - role_name: log_writer
    - user_name: fluentbit
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - opensearch: update_log_writer_role

# Create or ensure an OpensearchRole CR with permissions for the audit log indices
create_fluentbit_audit_role:
  opensearch.role_present:
    - name: create_fluentbit_audit_logs_role
    - role_name: audit-logs
    - index_name: openldap-audit-logs-*
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - opensearch: check_opensearch_health

# Map the Fluent Bit user to the audit logs role for write access (OpensearchUserRoleBinding CR)
map_fluentbit_user_to_audit_role:
  opensearch.user_role_mapping_present:
    - name: map_fluentbit_user_to_audit_logs_role
    - role_name: audit-logs
    - user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
    - namespace: {{ pillar.get('efk_namespace', 'efk') }}
    - cluster_name: opensearch
    - require:
      - opensearch: create_fluentbit_audit_role
